import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';
import 'package:veraprob/shared/utils/cnpj_validator.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/create_organization_form_data.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/org_preset_view_model.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/features/super_admin/presentation/screens/widgets/organization_wizard_steps.dart';
import 'package:veraprob/presentation/shared/widgets/domain_chip_input.dart';

/// 3-step wizard for creating a new tenant organization.
///
/// Step 1 — Dados Fiscais: legal/trade name, CNPJ, plan, timezone, currency.
/// Step 2 — Limites & Config: max vehicles, max contracts, capabilities editor,
///          speed/dwell defaults (labelled "Inicial (Padrão)"), reason field.
/// Step 3 — Convite Admin: initial admin email.
///
/// Pattern: ConsumerStatefulWidget + _currentStep + _highestStepReached
/// (mirrors declare_contract_plan_form.dart — INV-19: overlay modal).
///
/// **INV-4 / Lens 2:** No domain types are imported here.
/// - Capabilities are held as [OrgCapabilitiesViewModel] (application layer).
/// - Preset resolution goes through [OrgPresetViewModel] (application layer).
class CreateOrganizationWizard extends ConsumerStatefulWidget {
  /// Called when the wizard completes successfully (navigates to Tenants panel).
  final VoidCallback onSuccess;

  const CreateOrganizationWizard({super.key, required this.onSuccess});

  @override
  ConsumerState<CreateOrganizationWizard> createState() =>
      _CreateOrganizationWizardState();
}

class _CreateOrganizationWizardState
    extends ConsumerState<CreateOrganizationWizard> {
  int _currentStep = 0;
  int _highestStepReached = 0;

  bool _isSubmitting = false;

  // Step 1 controllers
  final _legalNameCtrl = TextEditingController();
  final _tradeNameCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _externalIdCtrl = TextEditingController();
  final _billingDayCtrl = TextEditingController();
  PlanType _selectedPlan = PlanType.starter;
  String _timezone = 'America/Sao_Paulo';
  String _currency = 'BRL';

  // CNPJ real-time uniqueness check + auto-fill
  String? _cnpjApiError;
  bool _cnpjChecking = false;
  bool _cnpjLookingUp = false;
  bool _cnpjAutoFilled = false;
  bool _cnpjAutoInactive = false;
  Timer? _cnpjDebounceTimer;

  // Step 2 controllers
  final _maxVehiclesCtrl = TextEditingController(text: '50');
  final _maxContractsCtrl = TextEditingController(text: '10');
  final _toolCostCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  // Step 2 operational config state — held as application-layer ViewModel,
  // never as OrgCapabilities (domain).
  String? _selectedPreset;
  OrgCapabilitiesViewModel _capabilities = OrgCapabilitiesViewModel.defaults;
  int _dwellTimeSeconds = 300;

  // Step 2 — Allowed Domains
  List<String> _allowedDomains = [];

  // Step 3 controllers
  final _adminEmailCtrl = TextEditingController();
  List<String> _adminEmails = [];

  // Form keys
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _cnpjCtrl.addListener(_onCnpjChanged);
  }

  @override
  void dispose() {
    _cnpjDebounceTimer?.cancel();
    _cnpjCtrl.removeListener(_onCnpjChanged);
    _legalNameCtrl.dispose();
    _tradeNameCtrl.dispose();
    _cnpjCtrl.dispose();
    _contactEmailCtrl.dispose();
    _externalIdCtrl.dispose();
    _billingDayCtrl.dispose();
    _maxVehiclesCtrl.dispose();
    _maxContractsCtrl.dispose();
    _toolCostCtrl.dispose();
    _reasonCtrl.dispose();
    _adminEmailCtrl.dispose();
    super.dispose();
  }

  /// Resolves capabilities from the selected preset via the application-layer
  /// façade [OrgPresetViewModel], without importing any domain type.
  void _onPresetChanged(String? preset) {
    setState(() {
      _selectedPreset = preset;
      if (preset == null) {
        _capabilities = OrgCapabilitiesViewModel.defaults;
      } else {
        // Apply preset as a template — existing manual overrides are replaced
        // by the template but remain editable afterwards.
        _capabilities = OrgPresetViewModel.resolveCapabilities(preset);
      }
    });
  }

  /// Toggles a single capability flag by key name.
  /// The preset is used as a template — SuperAdmin can override freely.
  void _onCapabilityToggled(String key, bool value) {
    setState(() {
      _capabilities = switch (key) {
        'allows_sealing' => _capabilities.copyWith(allowsSealing: value),
        'allows_loading' => _capabilities.copyWith(allowsLoading: value),
        'allows_cargo_check' => _capabilities.copyWith(allowsCargoCheck: value),
        'allows_incident' => _capabilities.copyWith(allowsIncident: value),
        'allows_doc' => _capabilities.copyWith(allowsDoc: value),
        'smart_classify' => _capabilities.copyWith(smartClassify: value),
        _ => _capabilities,
      };
    });
  }

  /// Updates the kinematic speed initial default.
  void _onSpeedChanged(double value) {
    setState(() {
      _capabilities = _capabilities.copyWith(
        maxKinematicSpeedKmh: value, // Physical Metric - Double Required
      );
    });
  }

  void _onCnpjChanged() {
    _cnpjDebounceTimer?.cancel();
    final digits = _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 14) {
      if (_cnpjApiError != null || _cnpjChecking) {
        setState(() {
          _cnpjApiError = null;
          _cnpjChecking = false;
        });
      }
      return;
    }

    // Structural validation (immediate check-digit check)
    if (!CnpjValidator.isValid(digits)) {
      if (_cnpjApiError != null || _cnpjChecking) {
        setState(() {
          _cnpjApiError = null;
          _cnpjChecking = false;
        });
      }
      return;
    }

    setState(() {
      _cnpjChecking = true;
      _cnpjApiError = null;
      _cnpjAutoFilled = false;
      _cnpjAutoInactive = false;
    });
    _cnpjDebounceTimer = Timer(
      const Duration(milliseconds: 600),
      _checkCnpjExists,
    );
  }

  Future<void> _checkCnpjExists() async {
    final digits = _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '');
    try {
      // Uniqueness check and ReceitaWS lookup run in parallel.
      setState(() => _cnpjLookingUp = true);
      final checkFuture = ref
          .read(superAdminRepositoryProvider)
          .checkCnpjExists(digits);
      final lookupFuture = ref.read(cnpjLookupServiceProvider).lookup(digits);
      final exists = await checkFuture;
      // lookup() returns CnpjCompanyData? — destructure to primitives immediately
      // so the domain VO never persists as widget state or widget parameter.
      final lookup = await lookupFuture;
      final autoFilled = lookup != null;
      final autoInactive = lookup != null && !lookup.isActive;
      if (!mounted) return;

      setState(() {
        _cnpjChecking = false;
        _cnpjLookingUp = false;
        _cnpjApiError = exists ? 'CNPJ já cadastrado no sistema' : null;
        _cnpjAutoFilled = autoFilled;
        _cnpjAutoInactive = autoInactive;
      });

      // Auto-fill only when CNPJ is not already registered.
      if (!exists && lookup != null) {
        if (lookup.legalName != null && _legalNameCtrl.text.trim().isEmpty) {
          _legalNameCtrl.text = lookup.legalName!;
        }
        if (lookup.tradeName != null && _tradeNameCtrl.text.trim().isEmpty) {
          _tradeNameCtrl.text = lookup.tradeName!.isNotEmpty
              ? lookup.tradeName!
              : lookup.legalName ?? '';
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cnpjChecking = false;
        _cnpjLookingUp = false;
      });
    }
  }

  bool _validateStep1() {
    if (!(_step1Key.currentState?.validate() ?? false)) return false;
    final cnpjDigits = _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cnpjDigits.length != 14) return false;
    if (_cnpjChecking || _cnpjApiError != null) return false;
    return true;
  }

  bool _validateStep2() {
    if (!(_step2Key.currentState?.validate() ?? false)) return false;
    return BrlCurrencyInputFormatter.toCents(_toolCostCtrl.text) != null;
  }

  bool _validateStep3() => _adminEmails.isNotEmpty;

  void _goToStep(int step) {
    if (step > _currentStep) {
      // Validate before advancing
      if (_currentStep == 0 && !_validateStep1()) return;
      if (_currentStep == 1 && !_validateStep2()) return;
    }
    setState(() {
      _currentStep = step;
      if (step > _highestStepReached) _highestStepReached = step;
    });
  }

  Future<void> _submit() async {
    // If the user typed an email but forgot to press Enter, add it automatically
    final pendingEmail = _adminEmailCtrl.text.trim().toLowerCase();
    if (pendingEmail.isNotEmpty &&
        pendingEmail.contains('@') &&
        !_adminEmails.contains(pendingEmail)) {
      setState(() => _adminEmails.add(pendingEmail));
      _adminEmailCtrl.clear();
    }

    if (!_validateStep3()) return;

    final superAdminId = ref.read(currentSuperAdminIdProvider);
    if (superAdminId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão expirada. Faça login novamente.'),
          backgroundColor: VeraProbColors.error,
        ),
      );
      return;
    }

    // ── Snapshot all controller values BEFORE any async gap (INV-7) ──────────
    // Prevents race conditions where setState/rebuild could contaminate
    // controller text between validation and submission.
    final snapshotLegalName = _legalNameCtrl.text.trim();
    final snapshotTradeName = _tradeNameCtrl.text.trim();
    final snapshotCnpj = _cnpjCtrl.text.trim();
    final snapshotMaxVehicles = _maxVehiclesCtrl.text.trim();
    final snapshotMaxContracts = _maxContractsCtrl.text.trim();
    final snapshotToolCost = _toolCostCtrl.text;
    final snapshotReason = _reasonCtrl.text.trim();
    final snapshotContactEmail = _contactEmailCtrl.text.trim();
    final snapshotExternalId = _externalIdCtrl.text.trim();
    final snapshotBillingDay = _billingDayCtrl.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final handler = ref.read(createOrganizationHandlerProvider);

      final cmd = CreateOrganizationFormData(
        legalName: snapshotLegalName,
        tradeName: snapshotTradeName,
        cnpj: snapshotCnpj,
        timezone: _timezone,
        currencyCode: _currency,
        planType: _selectedPlan,
        maxVehicles: int.parse(snapshotMaxVehicles),
        maxActiveContracts: int.parse(snapshotMaxContracts),
        adminEmails: _adminEmails,
        superAdminUserId: superAdminId,
        capabilities: _capabilities,
        toolCostCents: BrlCurrencyInputFormatter.toCents(snapshotToolCost),
        dwellTimeSeconds: _dwellTimeSeconds,
        reason: snapshotReason,
        contactEmail: snapshotContactEmail.isEmpty
            ? null
            : snapshotContactEmail,
        externalId: snapshotExternalId.isEmpty ? null : snapshotExternalId,
        billingDay: snapshotBillingDay.isEmpty
            ? null
            : int.tryParse(snapshotBillingDay),
        allowedDomains: _allowedDomains,
      ).toCommand();

      final result = await handler.handle(cmd);

      if (!mounted) return;

      // Capturar messenger e URL antes do showDialog (contexto seguro)
      final messenger = ScaffoldMessenger.of(context);

      String baseUrl = 'http://localhost';
      try {
        baseUrl = Uri.base.origin;
      } catch (_) {}

      // Build per-email invite URLs — one token per admin (INV-27 per-identity).
      final inviteUrls = <String, String>{};
      for (var i = 0; i < _adminEmails.length; i++) {
        final token = i < result.invitationTokens.length
            ? result.invitationTokens[i]
            : result.firstInvitationToken;
        inviteUrls[_adminEmails[i]] = '$baseUrl/accept-invite?token=$token';
      }

      // Fire invitation emails — silent failure (link in dialog is the fallback)
      for (final entry in inviteUrls.entries) {
        unawaited(
          handler.sendInviteNotification(
            email: entry.key,
            inviteUrl: entry.value,
            orgName: _tradeNameCtrl.text.trim(),
          ),
        );
      }

      // Stop loader before showing dialog, otherwise pumpAndSettle times out
      if (mounted) {
        setState(() => _isSubmitting = false);
      }

      // Success dialog
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) =>
            _buildSuccessDialog(inviteUrls, messenger, result.orgApiSecret),
      );

      if (mounted) {
        // Invalidate health snapshot to refresh the tenant list
        ref.invalidate(tenantHealthSnapshotProvider);
        widget.onSuccess();
      }
    } on DomainException catch (e) {
      if (!mounted) return;
      final message = _mapErrorMessage(e.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: VeraProbColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Erro inesperado ao processar solicitação. Tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _mapErrorMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('already_exists') || lower.contains('já existe')) {
      if (lower.contains('invite') || lower.contains('convite')) {
        return 'Um convite já foi enviado para um destes administradores.';
      }
      if (lower.contains('cnpj')) {
        return 'Este CNPJ já está cadastrado no sistema.';
      }
      return 'Este registro já existe no sistema.';
    }
    if (lower.contains('permission') || lower.contains('unauthorized')) {
      return 'Você não tem permissão para realizar esta operação.';
    }
    // Remove technical prefix if present (e.g. "DomainException: message")
    return raw.replaceAll(RegExp(r'^.*Exception: '), '').trim();
  }

  Widget _buildSuccessDialog(
    Map<String, String> inviteUrls,
    ScaffoldMessengerState messenger,
    String? orgApiSecret,
  ) {
    return AlertDialog(
      icon: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            color: VeraProbColors.success,
            size: 56,
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Fechar e voltar para Tenants',
            ),
          ),
        ],
      ),
      title: const Text('Organização Criada!'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(VeraProbSpacing.sm),
              decoration: BoxDecoration(
                color: VeraProbColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.business,
                    size: 20,
                    color: VeraProbColors.primary,
                  ),
                  const SizedBox(width: VeraProbSpacing.sm),
                  Expanded(
                    child: Text(
                      _tradeNameCtrl.text.trim(),
                      style: VeraProbTypography.sectionTitle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: VeraProbSpacing.md),
            Text(
              'Links de convite por administrador:',
              style: VeraProbTypography.sectionTitle.copyWith(fontSize: 13),
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            ...inviteUrls.entries.map(
              (entry) => Container(
                margin: const EdgeInsets.only(bottom: VeraProbSpacing.sm),
                padding: const EdgeInsets.all(VeraProbSpacing.sm),
                decoration: BoxDecoration(
                  color: VeraProbColors.surfaceElevated.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VeraProbColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: VeraProbTypography.sectionTitle.copyWith(
                              fontSize: 12,
                              color: VeraProbColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            entry.value,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: VeraProbColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: VeraProbSpacing.xs),
                    IconButton(
                      icon: const Icon(Icons.copy_all, size: 20),
                      tooltip: 'Copiar link de ${entry.key}',
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        await Clipboard.setData(
                          ClipboardData(text: entry.value),
                        );
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Link de ${entry.key} copiado!'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            Container(
              padding: const EdgeInsets.all(VeraProbSpacing.sm),
              decoration: BoxDecoration(
                color: VeraProbColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: VeraProbColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: VeraProbColors.warning,
                    semanticLabel: 'Informação importante',
                  ),
                  const SizedBox(width: VeraProbSpacing.sm),
                  Expanded(
                    child: Text(
                      'Envie cada link ao respectivo administrador para definição de senha.',
                      style: VeraProbTypography.bodySmall.copyWith(
                        color: VeraProbColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (orgApiSecret != null) ...[
              const SizedBox(height: VeraProbSpacing.md),
              _SecretRevealSection(secret: orgApiSecret, messenger: messenger),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: VeraProbColors.primary,
            minimumSize: const Size(120, 44),
          ),
          child: const Text('Concluir'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stepper(
      type: MediaQuery.sizeOf(context).width < 720
          ? StepperType.vertical
          : StepperType.horizontal,
      currentStep: _currentStep,
      onStepTapped: (step) {
        if (step <= _highestStepReached) _goToStep(step);
      },
      controlsBuilder: _buildControls,
      steps: [
        Step(
          title: const Text('Dados Fiscais'),
          isActive: _currentStep >= 0,
          state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          content: Step1FiscalData(
            formKey: _step1Key,
            legalNameCtrl: _legalNameCtrl,
            tradeNameCtrl: _tradeNameCtrl,
            cnpjCtrl: _cnpjCtrl,
            selectedPlan: _selectedPlan,
            timezone: _timezone,
            currency: _currency,
            cnpjApiError: _cnpjApiError,
            cnpjChecking: _cnpjChecking || _cnpjLookingUp,
            cnpjAutoFilled: _cnpjAutoFilled,
            cnpjAutoInactive: _cnpjAutoInactive,
            onPlanChanged: (p) => setState(() => _selectedPlan = p),
            onTimezoneChanged: (t) => setState(() => _timezone = t),
            onCurrencyChanged: (c) => setState(() => _currency = c),
            contactEmailCtrl: _contactEmailCtrl,
            externalIdCtrl: _externalIdCtrl,
            billingDayCtrl: _billingDayCtrl,
          ),
        ),
        Step(
          title: const Text('Limites'),
          isActive: _currentStep >= 1,
          state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Step2Limits(
                formKey: _step2Key,
                maxVehiclesCtrl: _maxVehiclesCtrl,
                maxContractsCtrl: _maxContractsCtrl,
                toolCostCtrl: _toolCostCtrl,
                reasonCtrl: _reasonCtrl,
                tradeName: _tradeNameCtrl.text,
                planLabel: _selectedPlan.label,
                selectedPreset: _selectedPreset,
                capabilities: _capabilities,
                dwellTimeSeconds: _dwellTimeSeconds,
                onPresetChanged: _onPresetChanged,
                onDwellChanged: (v) => setState(() => _dwellTimeSeconds = v),
                onCapabilityToggled: _onCapabilityToggled,
                onSpeedChanged: _onSpeedChanged,
              ),
              const SizedBox(height: VeraProbSpacing.md),
              const Divider(color: VeraProbColors.border),
              const SizedBox(height: VeraProbSpacing.sm),
              Text(
                'Segurança · Domínios Permitidos',
                style: VeraProbTypography.sectionTitle,
              ),
              const SizedBox(height: VeraProbSpacing.xs),
              Text(
                'E-mails de acesso restritos a estes domínios (opcional).',
                style: VeraProbTypography.bodySmall,
              ),
              const SizedBox(height: VeraProbSpacing.sm),
              DomainChipInput(
                initialDomains: _allowedDomains,
                onChanged: (domains) =>
                    setState(() => _allowedDomains = domains),
                hintText: 'ex: empresa.com.br',
              ),
              const SizedBox(height: VeraProbSpacing.sm),
            ],
          ),
        ),
        Step(
          title: const Text('Convite Admin'),
          isActive: _currentStep >= 2,
          state: StepState.indexed,
          content: Step3AdminInvite(
            formKey: _step3Key,
            emailCtrl: _adminEmailCtrl,
            adminEmails: _adminEmails,
            onEmailsChanged: (emails) => setState(() => _adminEmails = emails),
            tradeName: _tradeNameCtrl.text,
            planLabel: _selectedPlan.label,
            maxVehicles: _maxVehiclesCtrl.text,
            maxContracts: _maxContractsCtrl.text,
            isSubmitting: _isSubmitting,
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, ControlsDetails details) {
    final isLast = _currentStep == 2;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _isSubmitting
                  ? null
                  : () => _goToStep(_currentStep - 1),
              child: const Text('Voltar'),
            ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : isLast
                ? _submit
                : () => _goToStep(_currentStep + 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: VeraProbColors.superAdminSurface,
              foregroundColor: Colors.white,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isLast ? 'Criar e Enviar Convite' : 'Próximo'),
          ),
        ],
      ),
    );
  }
}

/// One-time HMAC secret reveal section (INV-28).
///
/// Displayed in the success dialog when [CreateOrganizationResult.orgApiSecret]
/// is non-null. The plain-text secret is shown exactly once and never stored.
class _SecretRevealSection extends StatelessWidget {
  final String secret;
  final ScaffoldMessengerState messenger;

  const _SecretRevealSection({required this.secret, required this.messenger});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber, size: 16, color: VeraProbColors.error),
              SizedBox(width: 6),
              Text(
                'Chave de API da Organização (única exibição)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: VeraProbColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  secret,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: VeraProbColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_all, size: 16),
                tooltip: 'Copiar chave',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: secret));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Chave copiada!')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Copie agora. Este segredo não será exibido novamente.',
            style: TextStyle(fontSize: 11, color: VeraProbColors.error),
          ),
        ],
      ),
    );
  }
}
