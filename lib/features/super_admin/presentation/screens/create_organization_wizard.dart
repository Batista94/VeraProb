import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/cnpj_input_formatter.dart';
import '../../../../core/utils/cnpj_validator.dart';
import '../../../../domain/super_admin/create_organization_command.dart';
import '../../../../domain/super_admin/plan_type.dart';
import '../../../../domain/sla_audit/domain_exception.dart';
import '../../../../infrastructure/providers/super_admin_providers.dart';
import '../../../../state/providers/super_admin_auth_providers.dart';

// Re-use the same BR timezones list from the main wizard.
const _kBrTimezones = [
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Belem',
  'America/Fortaleza',
  'America/Recife',
  'America/Noronha',
  'America/Cuiaba',
  'America/Porto_Velho',
  'America/Rio_Branco',
  'America/Boa_Vista',
];

const _kCurrencies = ['BRL', 'USD', 'EUR'];

/// 3-step wizard for creating a new tenant organization.
///
/// Step 1 — Dados Fiscais: legal/trade name, CNPJ, plan, timezone, currency.
/// Step 2 — Limites de Uso: max vehicles, max active contracts.
/// Step 3 — Convite Admin: initial admin email.
///
/// Pattern: ConsumerStatefulWidget + _currentStep + _highestStepReached
/// (mirrors declare_contract_plan_form.dart — INV-19: overlay modal).
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

  // Step 3 controllers
  final _adminEmailCtrl = TextEditingController();

  // Step 1 key
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
    _maxVehiclesCtrl.dispose();
    _maxContractsCtrl.dispose();
    _adminEmailCtrl.dispose();
    super.dispose();
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
      setState(() {
        _cnpjApiError = 'CNPJ inválido';
        _cnpjChecking = false;
      });
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

  bool _validateStep2() => _step2Key.currentState?.validate() ?? false;

  bool _validateStep3() => _step3Key.currentState?.validate() ?? false;

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

    setState(() => _isSubmitting = true);

    try {
      final handler = ref.read(createOrganizationHandlerProvider);

      final cmd = CreateOrganizationCommand(
        legalName: _legalNameCtrl.text.trim(),
        tradeName: _tradeNameCtrl.text.trim(),
        cnpj: _cnpjCtrl.text.trim(),
        timezone: _timezone,
        currencyCode: _currency,
        planType: _selectedPlan.dbValue,
        maxVehicles: int.parse(_maxVehiclesCtrl.text.trim()),
        maxActiveContracts: int.parse(_maxContractsCtrl.text.trim()),
        initialAdminEmail: _adminEmailCtrl.text.trim().toLowerCase(),
        superAdminUserId: superAdminId,
      );

      final result = await handler.handle(cmd);

      if (!mounted) return;

      // Capturar messenger e URL antes do showDialog (contexto seguro)
      final messenger = ScaffoldMessenger.of(context);
      final inviteUrl =
          '${Uri.base.origin}/accept-invite?token=${result.invitationToken}';

      // Fire invitation email — silent failure (link in dialog is the fallback)
      unawaited(
        handler.sendInviteNotification(
          email: cmd.initialAdminEmail,
          inviteUrl: inviteUrl,
          orgName: cmd.tradeName,
        ),
      );

      // Success dialog
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _buildSuccessDialog(inviteUrl, messenger),
      );

      // Invalidate health snapshot to refresh the tenant list
      ref.invalidate(tenantHealthSnapshotProvider);
    } on DomainException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro inesperado: $e'),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildSuccessDialog(
    String inviteUrl,
    ScaffoldMessengerState messenger,
  ) {
    return AlertDialog(
      icon: const Icon(
        Icons.check_circle,
        color: VeraProbColors.success,
        size: 48,
      ),
      title: const Text('Organização Criada!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Organização: ${_tradeNameCtrl.text.trim()}'),
          const SizedBox(height: 8),
          Text('Admin convidado para: ${_adminEmailCtrl.text.trim()}'),
          const SizedBox(height: 16),
          const Text(
            'Link de convite do Admin:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  inviteUrl,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                tooltip: 'Copiar link',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: inviteUrl));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Link copiado!')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: VeraProbColors.warning.withValues(alpha: 0.5),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: VeraProbColors.warning,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Envie este link ao administrador. Ele deve acessá-lo para definir sua senha.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onSuccess();
          },
          child: const Text('Ver Tenants'),
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
          content: _Step1FiscalData(
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
          ),
        ),
        Step(
          title: const Text('Limites'),
          isActive: _currentStep >= 1,
          state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          content: _Step2Limits(
            formKey: _step2Key,
            maxVehiclesCtrl: _maxVehiclesCtrl,
            maxContractsCtrl: _maxContractsCtrl,
            // Read-only summary from Step 1
            tradeName: _tradeNameCtrl.text,
            planLabel: _selectedPlan.label,
          ),
        ),
        Step(
          title: const Text('Convite Admin'),
          isActive: _currentStep >= 2,
          state: StepState.indexed,
          content: _Step3AdminInvite(
            formKey: _step3Key,
            adminEmailCtrl: _adminEmailCtrl,
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

// ── Step 1: Fiscal Data ───────────────────────────────────────────────────────

class _Step1FiscalData extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController legalNameCtrl;
  final TextEditingController tradeNameCtrl;
  final TextEditingController cnpjCtrl;
  final PlanType selectedPlan;
  final String timezone;
  final String currency;
  final String? cnpjApiError;
  final bool cnpjChecking;
  final bool cnpjAutoFilled;
  final bool cnpjAutoInactive;
  final ValueChanged<PlanType> onPlanChanged;
  final ValueChanged<String> onTimezoneChanged;
  final ValueChanged<String> onCurrencyChanged;

  const _Step1FiscalData({
    required this.formKey,
    required this.legalNameCtrl,
    required this.tradeNameCtrl,
    required this.cnpjCtrl,
    required this.selectedPlan,
    required this.timezone,
    required this.currency,
    required this.cnpjApiError,
    required this.cnpjChecking,
    required this.cnpjAutoFilled,
    required this.cnpjAutoInactive,
    required this.onPlanChanged,
    required this.onTimezoneChanged,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: legalNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Razão Social *',
              hintText: 'Ex: Transportes Silva Ltda.',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: tradeNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome Fantasia *',
              hintText: 'Ex: Silva Logística',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: cnpjCtrl,
            decoration: InputDecoration(
              labelText: 'CNPJ *',
              hintText: '00.000.000/0000-00',
              suffixIcon: cnpjChecking
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : cnpjApiError != null
                  ? const Icon(Icons.error_outline, color: VeraProbColors.error)
                  : null,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              CnpjInputFormatter(),
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              final digits = v.replaceAll(RegExp(r'\D'), '');
              if (digits.length != 14) return 'CNPJ deve ter 14 dígitos';
              if (!CnpjValidator.isValid(digits)) return 'CNPJ inválido';
              return null;
            },
          ),
          if (cnpjApiError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12),
              child: Text(
                cnpjApiError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (cnpjAutoFilled && cnpjApiError == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: VeraProbColors.success,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Dados preenchidos via ReceitaWS',
                        style: TextStyle(
                          fontSize: 12,
                          color: VeraProbColors.success,
                        ),
                      ),
                    ],
                  ),
                  if (cnpjAutoInactive)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          size: 14,
                          color: VeraProbColors.warning,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Empresa inativa na Receita Federal',
                          style: TextStyle(
                            fontSize: 12,
                            color: VeraProbColors.warning,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('Plano *', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          SegmentedButton<PlanType>(
            segments: PlanType.values
                .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                .toList(),
            selected: {selectedPlan},
            onSelectionChanged: (s) => onPlanChanged(s.first),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: timezone,
            decoration: const InputDecoration(labelText: 'Fuso Horário *'),
            items: _kBrTimezones
                .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
                .toList(),
            onChanged: (v) => onTimezoneChanged(v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: currency,
            decoration: const InputDecoration(labelText: 'Moeda *'),
            items: _kCurrencies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => onCurrencyChanged(v!),
          ),
        ],
      ),
    );
  }
}

// ── Step 2: Limits ────────────────────────────────────────────────────────────

class _Step2Limits extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController maxVehiclesCtrl;
  final TextEditingController maxContractsCtrl;
  final String tradeName;
  final String planLabel;

  const _Step2Limits({
    required this.formKey,
    required this.maxVehiclesCtrl,
    required this.maxContractsCtrl,
    required this.tradeName,
    required this.planLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Read-only summary from Step 1
          if (tradeName.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VeraProbColors.superAdminSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(
                    Icons.business,
                    size: 16,
                    color: VeraProbColors.secondary,
                  ),
                  Text(
                    '$tradeName — Plano $planLabel',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: maxVehiclesCtrl,
            decoration: const InputDecoration(
              labelText: 'Máximo de Veículos *',
              hintText: 'Ex: 50',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              final n = int.tryParse(v);
              if (n == null || n < 1) return 'Deve ser >= 1';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: maxContractsCtrl,
            decoration: const InputDecoration(
              labelText: 'Máximo de Contratos Ativos *',
              hintText: 'Ex: 10',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              final n = int.tryParse(v);
              if (n == null || n < 1) return 'Deve ser >= 1';
              return null;
            },
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Admin Invite ──────────────────────────────────────────────────────

class _Step3AdminInvite extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController adminEmailCtrl;
  final String tradeName;
  final String planLabel;
  final String maxVehicles;
  final String maxContracts;
  final bool isSubmitting;

  const _Step3AdminInvite({
    required this.formKey,
    required this.adminEmailCtrl,
    required this.tradeName,
    required this.planLabel,
    required this.maxVehicles,
    required this.maxContracts,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Read-only org summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VeraProbColors.superAdminSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow(
                  icon: Icons.business,
                  label: 'Empresa',
                  value: tradeName,
                ),
                _SummaryRow(
                  icon: Icons.star_outline,
                  label: 'Plano',
                  value: planLabel,
                ),
                _SummaryRow(
                  icon: Icons.directions_car,
                  label: 'Máx. Veículos',
                  value: maxVehicles,
                ),
                _SummaryRow(
                  icon: Icons.description_outlined,
                  label: 'Máx. Contratos',
                  value: maxContracts,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: adminEmailCtrl,
            decoration: const InputDecoration(
              labelText: 'E-mail do Admin Inicial *',
              hintText: 'admin@empresa.com.br',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
              if (!v.trim().contains('@')) return 'E-mail inválido';
              return null;
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: VeraProbColors.warning.withValues(alpha: 0.5),
              ),
            ),
            child: const Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: VeraProbColors.warning,
                ),
                Text(
                  'Um convite válido por 7 dias será enviado para este e-mail com permissão de Administrador.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: VeraProbColors.secondary),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(color: VeraProbColors.textSecondary),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

