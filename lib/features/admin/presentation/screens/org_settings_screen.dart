import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/admin/org_capabilities.dart';
import 'package:veraprob/application/admin/update_org_operational_params_command.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/application/admin/update_org_settings_command.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/org_settings/org_settings_header.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/org_settings/general_settings_section.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/org_settings/capabilities_audit_list.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/org_settings/operational_parameters_panel.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/org_settings/super_admin_security_guard.dart';

/// Screen for editing organization-wide settings.
///
/// Split into two sections:
///   1. Configurações Gerais (name, timezone, currency, logo, capabilities)
///   2. Parâmetros Operacionais (dwell_time_seconds, max_kinematic_speed_kmh)
///      — configurações de negócio editáveis pelo Admin da Org.
///
/// Section widgets live under `widgets/org_settings/` — this screen owns the
/// mutable state (controllers, `AsyncValue` orchestration) and the save
/// handlers; sections are stateless and surface mutations via callbacks.
class OrgSettingsTab extends ConsumerStatefulWidget {
  const OrgSettingsTab({super.key});

  @override
  ConsumerState<OrgSettingsTab> createState() => _OrgSettingsTabState();
}

class _OrgSettingsTabState extends ConsumerState<OrgSettingsTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _timezoneController = TextEditingController();
  final _currencyController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _orgTypeController = TextEditingController();

  OrgCapabilities _capabilities = OrgCapabilities.defaults;
  OrgCapabilities? _originalCapabilities;
  final _capReasonController = TextEditingController();
  bool _isSaving = false;

  // ── Parâmetros Operacionais (editáveis pelo Admin da Org) ──────────────────
  final _opParamsFormKey = GlobalKey<FormState>();
  final _opReasonController = TextEditingController();
  int _dwellTimeSeconds = 300;
  double _maxKinematicSpeedKmh = 80.0; // Physical Metric - Double Required
  bool _opParamsInitialized = false;
  bool _isSavingOpParams = false;

  // ── Domínios Permitidos (SuperAdmin only) ──────────────────────────────────
  List<String> _allowedDomains = [];
  bool _domainsInitialized = false;
  bool _savingDomains = false;

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    _currencyController.dispose();
    _logoUrlController.dispose();
    _orgTypeController.dispose();
    _capReasonController.dispose();
    _opReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orgAsync = ref.watch(orgSettingsProvider);
    final userRole = ref.watch(currentUserRoleProvider);
    final isSuperAdmin = userRole == UserRole.superAdmin;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OrgSettingsHeader(),
          const SizedBox(height: 32),
          Expanded(
            child: switch (orgAsync) {
              AsyncData() => _buildLoadedBody(isSuperAdmin),
              AsyncLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
              AsyncError() => const Center(
                child: Text(
                  'Não foi possível carregar as configurações da organização.',
                  style: TextStyle(color: VeraProbColors.error),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }

  /// `AsyncData` arm: null guard, once-per-session state hydration, scroll body.
  ///
  /// The loaded organization is read as an inferred local (never naming the
  /// domain type) to keep the features layer free of `domain/` imports (INV-13).
  Widget _buildLoadedBody(bool isSuperAdmin) {
    final org = ref.watch(orgSettingsProvider).value;
    if (org == null) {
      return const Center(child: Text('Organização não encontrada'));
    }

    // Initialize controllers once — guard preserves user edits across rebuilds.
    if (_nameController.text.isEmpty && !_isSaving) {
      _nameController.text = org.name;
      _timezoneController.text = org.timezone;
      _currencyController.text = org.currencyCode;
      _logoUrlController.text = org.logoUrl ?? '';
      _orgTypeController.text = org.organizationType ?? '';
      _capabilities = org.capabilities;
      _originalCapabilities ??= org.capabilities;
    }

    // Initialize operational params once
    if (!_opParamsInitialized) {
      _dwellTimeSeconds = org.dwellTimeSeconds;
      _maxKinematicSpeedKmh =
          org.capabilities.maxKinematicSpeedKmh ??
          80.0; // Physical Metric - Double Required
      _opParamsInitialized = true;
    }

    if (!_domainsInitialized) {
      _allowedDomains = List<String>.from(org.allowedDomains);
      _domainsInitialized = true;
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Seção 1: Configurações Gerais ─────────────────────────────
            GeneralSettingsSection(
              formKey: _formKey,
              nameController: _nameController,
              timezoneController: _timezoneController,
              currencyController: _currencyController,
              logoUrlController: _logoUrlController,
              orgTypeController: _orgTypeController,
              isSuperAdmin: isSuperAdmin,
              isSaving: _isSaving,
              onSave: _save,
              capabilitiesChild: CapabilitiesAuditList(
                capabilities: _capabilities,
                originalCapabilities: _originalCapabilities,
                capReasonController: _capReasonController,
                onCapabilitiesChanged: (c) => setState(() => _capabilities = c),
              ),
            ),

            // ── Seção 2: Parâmetros Operacionais ──────────────────────────
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 24),
            OperationalParametersPanel(
              opParamsFormKey: _opParamsFormKey,
              dwellTimeSeconds: _dwellTimeSeconds,
              maxKinematicSpeedKmh:
                  _maxKinematicSpeedKmh, // Physical Metric - Double Required
              opReasonController: _opReasonController,
              isSavingOpParams: _isSavingOpParams,
              onDwellChanged: (v) => setState(() => _dwellTimeSeconds = v),
              onSpeedChanged: (v) => setState(
                () => _maxKinematicSpeedKmh =
                    v, // Physical Metric - Double Required
              ),
              onSave: _saveOpParams,
            ),

            // ── Seção 3: Domínios Permitidos (SuperAdmin only) ────────────
            SuperAdminSecurityGuard(
              isSuperAdmin: isSuperAdmin,
              allowedDomains: _allowedDomains,
              savingDomains: _savingDomains,
              onDomainsChanged: (domains) =>
                  setState(() => _allowedDomains = domains),
              onSave: _saveAllowedDomains,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final role = ref.read(currentUserRoleProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final capabilitiesChanged =
          _originalCapabilities != null &&
          _capabilities != _originalCapabilities;

      final command = UpdateOrgSettingsCommand(
        organizationId: orgId!,
        callerRole: role,
        name: role == UserRole.superAdmin ? _nameController.text.trim() : null,
        timezone: role == UserRole.superAdmin
            ? _timezoneController.text.trim()
            : null,
        currencyCode: role == UserRole.superAdmin
            ? _currencyController.text.trim()
            : null,
        logoUrl: _logoUrlController.text.trim().isEmpty
            ? null
            : _logoUrlController.text.trim(),
        organizationType: _orgTypeController.text.trim().isEmpty
            ? null
            : _orgTypeController.text.trim(),
        capabilities: capabilitiesChanged ? _capabilities : null,
        reason: capabilitiesChanged ? _capReasonController.text.trim() : null,
        sessionId: sessionId,
      );

      await ref.read(updateOrgSettingsHandlerProvider).handle(command);

      if (capabilitiesChanged) {
        _originalCapabilities = _capabilities;
        _capReasonController.clear();
      }
      ref.invalidate(orgSettingsProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Configurações salvas com sucesso!'),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar as configurações. Verifique os dados e tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveOpParams() async {
    if (!(_opParamsFormKey.currentState?.validate() ?? false)) return;

    setState(() => _isSavingOpParams = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final role = ref.read(currentUserRoleProvider);
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final command = UpdateOrgOperationalParamsCommand(
        organizationId: orgId!,
        callerRole: role,
        dwellTimeSeconds: _dwellTimeSeconds,
        maxKinematicSpeedKmh:
            _maxKinematicSpeedKmh, // Physical Metric - Double Required
        reason: _opReasonController.text.trim(),
        sessionId: sessionId,
      );

      await ref.read(updateOrgOperationalParamsHandlerProvider).handle(command);

      _opReasonController.clear();
      ref.invalidate(orgSettingsProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Parâmetros operacionais atualizados com sucesso!'),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar os parâmetros. Tente novamente mais tarde.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingOpParams = false);
    }
  }

  Future<void> _saveAllowedDomains() async {
    setState(() => _savingDomains = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final superAdminId = ref.read(currentSuperAdminIdProvider);
      if (orgId == null || superAdminId == null) return;

      await ref
          .read(superAdminRepositoryProvider)
          .updateAllowedDomains(orgId, _allowedDomains, superAdminId);

      ref.invalidate(orgSettingsProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Domínios atualizados com sucesso!'),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível salvar os domínios. Verifique a sintaxe e tente novamente.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDomains = false);
    }
  }
}
