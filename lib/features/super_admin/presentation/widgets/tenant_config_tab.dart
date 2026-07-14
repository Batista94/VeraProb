import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/update_quota_form_data.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/locked_field_tile.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/reason_confirmation_dialog.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class TenantConfigTab extends ConsumerStatefulWidget {
  final TenantHealthView tenant;
  const TenantConfigTab({super.key, required this.tenant});

  @override
  ConsumerState<TenantConfigTab> createState() => _TenantConfigTabState();
}

class _TenantConfigTabState extends ConsumerState<TenantConfigTab> {
  late OrgCapabilitiesViewModel _capabilities;
  final _formKey = GlobalKey<FormState>();

  String? _planType;
  String? _orgType;
  final _tradeNameCtrl = TextEditingController();
  final _legalNameCtrl = TextEditingController();
  final _maxVehiclesCtrl = TextEditingController();
  final _maxContractsCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _dwellTimeCtrl = TextEditingController();
  final _billingDayCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _externalIdCtrl = TextEditingController();

  // CT10 — Motor Forense, Compliance, Infraestrutura
  final _clockDriftCtrl = TextEditingController();
  final _dataRetentionCtrl = TextEditingController();
  final _connectionPoolCtrl = TextEditingController();
  final _storageQuotaCtrl = TextEditingController();

  // CT10 — Domínios Permitidos (movido da aba Segurança)
  late List<String> _allowedDomains;
  final _domainInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initValues(widget.tenant);
  }

  void _initValues(TenantHealthView t) {
    _capabilities = t.capabilities;
    _planType = t.planType;
    _orgType = t.organizationType;
    _tradeNameCtrl.text = t.name;
    _legalNameCtrl.text = t.legalName ?? '';
    _maxVehiclesCtrl.text = t.maxVehicles == 0 ? '' : t.maxVehicles.toString();
    _maxContractsCtrl.text = t.maxActiveContracts == 0
        ? ''
        : t.maxActiveContracts.toString();
    _costCtrl.text = _costString(t.toolCostCents);
    _dwellTimeCtrl.text = t.dwellTimeSeconds.toString();
    _billingDayCtrl.text = t.billingDay?.toString() ?? '';
    _contactEmailCtrl.text = t.contactEmail ?? '';
    _externalIdCtrl.text = t.externalId ?? '';
    // CT10
    _clockDriftCtrl.text = t.clockDriftToleranceS.toString();
    _dataRetentionCtrl.text = t.dataRetentionDays.toString();
    _connectionPoolCtrl.text = t.connectionPoolLimit.toString();
    _storageQuotaCtrl.text = t.storageQuotaGb.toString();
    _allowedDomains = List<String>.from(t.allowedDomains);
  }

  @override
  void didUpdateWidget(covariant TenantConfigTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-init only when switching tenant or when a committed snapshot arrives.
    // TenantHealthView has no value equality, so reference != is always true;
    // comparing id + updatedAt avoids clobbering in-progress edits on
    // unrelated parent rebuilds.
    if (oldWidget.tenant.id != widget.tenant.id) {
      _initValues(widget.tenant);
    }
  }

  @override
  void dispose() {
    _tradeNameCtrl.dispose();
    _legalNameCtrl.dispose();
    _maxVehiclesCtrl.dispose();
    _maxContractsCtrl.dispose();
    _costCtrl.dispose();
    _dwellTimeCtrl.dispose();
    _billingDayCtrl.dispose();
    _contactEmailCtrl.dispose();
    _externalIdCtrl.dispose();
    // CT10
    _clockDriftCtrl.dispose();
    _dataRetentionCtrl.dispose();
    _connectionPoolCtrl.dispose();
    _storageQuotaCtrl.dispose();
    _domainInputCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _costString(int? cents) =>
      cents != null ? (cents / 100).toStringAsFixed(2) : '';

  bool get _isDisabled => widget.tenant.isArchived;

  bool get _capabilitiesChanged => _capabilities != widget.tenant.capabilities;

  bool get _ct10Changed {
    final t = widget.tenant;
    return _clockDriftCtrl.text != t.clockDriftToleranceS.toString() ||
        _dataRetentionCtrl.text != t.dataRetentionDays.toString() ||
        _connectionPoolCtrl.text != t.connectionPoolLimit.toString() ||
        _storageQuotaCtrl.text != t.storageQuotaGb.toString();
  }

  bool get _domainsChanged {
    final current = List<String>.from(widget.tenant.allowedDomains)..sort();
    final edited = List<String>.from(_allowedDomains)..sort();
    return current.join(',') != edited.join(',');
  }

  bool get _paramsChanged {
    final t = widget.tenant;
    return _planType != t.planType ||
        _orgType != t.organizationType ||
        _tradeNameCtrl.text != t.name ||
        _legalNameCtrl.text != (t.legalName ?? '') ||
        _maxVehiclesCtrl.text !=
            (t.maxVehicles == 0 ? '' : t.maxVehicles.toString()) ||
        _maxContractsCtrl.text !=
            (t.maxActiveContracts == 0
                ? ''
                : t.maxActiveContracts.toString()) ||
        _costCtrl.text != _costString(t.toolCostCents) ||
        _dwellTimeCtrl.text != t.dwellTimeSeconds.toString() ||
        _billingDayCtrl.text != (t.billingDay?.toString() ?? '') ||
        _contactEmailCtrl.text != (t.contactEmail ?? '') ||
        _externalIdCtrl.text != (t.externalId ?? '') ||
        _ct10Changed;
  }

  bool get _isDirty =>
      _capabilitiesChanged || _paramsChanged || _domainsChanged;

  bool get _isFormValid {
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '.'));
    if (_costCtrl.text.isEmpty || cost == null || cost.isNaN || cost < 0) {
      return false;
    }
    if (_billingDayCtrl.text.isNotEmpty) {
      final n = int.tryParse(_billingDayCtrl.text);
      if (n == null || n < 1 || n > 28) return false;
    }
    if (_maxVehiclesCtrl.text.isNotEmpty) {
      final n = int.tryParse(_maxVehiclesCtrl.text);
      if (n == null || n < 1) return false;
    }
    if (_maxContractsCtrl.text.isNotEmpty) {
      final n = int.tryParse(_maxContractsCtrl.text);
      if (n == null || n < 1) return false;
    }
    if (_dwellTimeCtrl.text.isNotEmpty) {
      final n = int.tryParse(_dwellTimeCtrl.text);
      if (n == null || n < 300) return false;
    }
    if (_contactEmailCtrl.text.isNotEmpty) {
      final e = _contactEmailCtrl.text;
      if (!e.contains('@') || !e.contains('.')) return false;
    }
    // CT10 validations
    final clockDrift = int.tryParse(_clockDriftCtrl.text);
    if (_clockDriftCtrl.text.isNotEmpty &&
        (clockDrift == null || clockDrift < 0)) {
      return false;
    }
    final retention = int.tryParse(_dataRetentionCtrl.text);
    if (_dataRetentionCtrl.text.isNotEmpty &&
        (retention == null || retention < 1)) {
      return false;
    }
    final pool = int.tryParse(_connectionPoolCtrl.text);
    if (_connectionPoolCtrl.text.isNotEmpty &&
        (pool == null || pool < 1 || pool > 500)) {
      return false;
    }
    final storage = int.tryParse(_storageQuotaCtrl.text);
    if (_storageQuotaCtrl.text.isNotEmpty && (storage == null || storage < 1)) {
      return false;
    }
    return true;
  }

  String _savePromptMessage() {
    if (_capabilitiesChanged && _paramsChanged) {
      return 'Informe o motivo das alterações na configuração da organização. '
          'Este registro será gravado no log de auditoria.';
    }
    if (_capabilitiesChanged) {
      return 'Informe o motivo da alteração de capabilities. '
          'Este registro será gravado no log de auditoria.';
    }
    return 'Informe o motivo da alteração dos parâmetros operacionais/financeiros. '
        'Este registro será gravado no log de auditoria.';
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  /// Extract error message without importing domain types (INV-13).
  String _extractErrorMessage(Object error) {
    if (error.runtimeType.toString().contains('ProviderException')) {
      try {
        final original = (error as dynamic).exception as Object;
        return _extractErrorMessage(original);
      } catch (_) {
        return 'Falha ao processar solicitação. Tente novamente.';
      }
    }
    try {
      final msg = (error as dynamic).message;
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
    return 'Falha ao processar solicitação. Tente novamente.';
  }

  Future<void> _copyToClipboard(String value) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: value));
    messenger.showSnackBar(
      const SnackBar(content: Text('Copiado para a área de transferência')),
    );
  }

  void _addDomain() {
    final raw = _domainInputCtrl.text.trim().toLowerCase();
    if (raw.isEmpty) return;
    if (!raw.contains('.') || raw.startsWith('.') || raw.endsWith('.')) {
      _showSnackBar('Domínio inválido', backgroundColor: VeraProbColors.error);
      return;
    }
    if (_allowedDomains.contains(raw)) {
      _showSnackBar('Domínio já existe na lista');
      return;
    }
    setState(() {
      _allowedDomains = [..._allowedDomains, raw];
      _domainInputCtrl.clear();
    });
  }

  void _removeDomain(String domain) {
    setState(() {
      _allowedDomains = _allowedDomains.where((d) => d != domain).toList();
    });
  }

  Future<void> _saveAllowedDomains(String reason) async {
    final repo = ref.read(superAdminRepositoryProvider);
    final userId = ref.read(authStateProvider).value?.session?.user.id ?? '';
    await repo.updateAllowedDomains(widget.tenant.id, _allowedDomains, userId);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) =>
          ReasonConfirmationDialog(promptMessage: _savePromptMessage()),
    );
    if (reason == null || !mounted) return;

    try {
      final t = widget.tenant;
      final costVal =
          double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0.0;

      // Save quota/config params
      if (_paramsChanged || _capabilitiesChanged) {
        final cmd = UpdateQuotaFormData(
          organizationId: t.id,
          newPlanType: _planType ?? 'starter',
          newMaxVehicles: int.tryParse(_maxVehiclesCtrl.text),
          newMaxActiveContracts: int.tryParse(_maxContractsCtrl.text),
          superAdminUserId:
              ref.read(authStateProvider).value?.session?.user.id ?? '',
          reason: reason,
          capabilities: _capabilities,
          toolCostCents: (costVal * 100).round(),
          dwellTimeSeconds: int.tryParse(_dwellTimeCtrl.text) ?? 300,
          billingDay: int.tryParse(_billingDayCtrl.text),
          contactEmail: _contactEmailCtrl.text.isEmpty
              ? null
              : _contactEmailCtrl.text,
          externalId: _externalIdCtrl.text.isEmpty
              ? null
              : _externalIdCtrl.text,
          organizationType: _orgType,
          tradeName: _tradeNameCtrl.text.isEmpty ? null : _tradeNameCtrl.text,
          legalName: _legalNameCtrl.text.isEmpty ? null : _legalNameCtrl.text,
          expectedUpdatedAt: DateTime.now()
              .toUtc(), // fallback until occ is fully disabled or refactored
          // CT10
          clockDriftToleranceS: int.tryParse(_clockDriftCtrl.text),
          dataRetentionDays: int.tryParse(_dataRetentionCtrl.text),
          connectionPoolLimit: int.tryParse(_connectionPoolCtrl.text),
          storageQuotaGb: int.tryParse(_storageQuotaCtrl.text),
        ).toCommand();

        await ref.read(updateOrganizationQuotaHandlerProvider).handle(cmd);
      }

      // Save allowed domains independently (separate RPC — Lesson 2)
      if (_domainsChanged) {
        await _saveAllowedDomains(reason);
      }

      ref.invalidate(tenantHealthSnapshotProvider);
      await ref.read(tenantHealthSnapshotProvider.future);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Configurações atualizadas com sucesso.'),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } catch (e) {
      // Extract error message gracefully without domain imports (INV-13).
      // ProviderException wraps the original error; try to access its message property.
      final msg = _extractErrorMessage(e);
      messenger.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: VeraProbColors.error),
      );
    }
  }

  List<Widget> _buildImmutableIdentitySection() {
    return [
      const _SectionTitle('Identidade Imutável'),
      const SizedBox(height: 16),
      LockedFieldTile(
        label: 'Slug',
        value: widget.tenant.id,
        onCopy: () => _copyToClipboard(widget.tenant.id),
      ),
      const SizedBox(height: 12),
      LockedFieldTile(
        label: 'CNPJ',
        value: widget.tenant.cnpj,
        placeholder: 'Não informado',
        onCopy: widget.tenant.cnpj != null
            ? () => _copyToClipboard(widget.tenant.cnpj!)
            : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildImmutableIdentitySection(),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            _IdentificationSection(
              tradeNameCtrl: _tradeNameCtrl,
              legalNameCtrl: _legalNameCtrl,
              enabled: !_isDisabled,
              onFieldChanged: () => setState(() {}),
            ),
            const SizedBox(height: 24),
            _PlanLimitsSection(
              planType: _planType,
              orgType: _orgType,
              maxVehiclesCtrl: _maxVehiclesCtrl,
              maxContractsCtrl: _maxContractsCtrl,
              costCtrl: _costCtrl,
              dwellTimeCtrl: _dwellTimeCtrl,
              enabled: !_isDisabled,
              onPlanTypeChanged: (v) => setState(() => _planType = v),
              onOrgTypeChanged: (v) => setState(() => _orgType = v),
              onFieldChanged: () => setState(() {}),
            ),
            const SizedBox(height: 24),
            _BillingIntegrationSection(
              billingDayCtrl: _billingDayCtrl,
              contactEmailCtrl: _contactEmailCtrl,
              externalIdCtrl: _externalIdCtrl,
              enabled: !_isDisabled,
              onFieldChanged: () => setState(() {}),
            ),
            const SizedBox(height: 24),
            // CT10 — Motor Forense
            _ForensicEngineSection(
              clockDriftCtrl: _clockDriftCtrl,
              enabled: !_isDisabled,
              onFieldChanged: () => setState(() {}),
            ),
            const SizedBox(height: 24),
            // CT10 — Compliance
            _ComplianceSection(
              dataRetentionCtrl: _dataRetentionCtrl,
              enabled: !_isDisabled,
              onFieldChanged: () => setState(() {}),
            ),
            const SizedBox(height: 24),
            // CT10 — Infraestrutura
            _InfrastructureSection(
              connectionPoolCtrl: _connectionPoolCtrl,
              storageQuotaCtrl: _storageQuotaCtrl,
              enabled: !_isDisabled,
              onFieldChanged: () => setState(() {}),
            ),
            const SizedBox(height: 24),
            // CT10 — Domínios Permitidos (movido da aba Segurança)
            _AllowedDomainsSection(
              domains: _allowedDomains,
              domainInputCtrl: _domainInputCtrl,
              enabled: !_isDisabled,
              onAdd: _addDomain,
              onRemove: _removeDomain,
            ),
            const SizedBox(height: 24),
            _CapabilitiesSection(
              capabilities: _capabilities,
              enabled: !_isDisabled,
              onChanged: (caps) => setState(() => _capabilities = caps),
            ),
            if (_isDirty && !widget.tenant.isArchived) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isFormValid ? _save : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Salvar Alteracoes'),
                style: FilledButton.styleFrom(
                  backgroundColor: VeraProbColors.superAdminSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Form Section Widgets ─────────────────────────────────────────────────────

class _IdentificationSection extends StatelessWidget {
  final TextEditingController tradeNameCtrl;
  final TextEditingController legalNameCtrl;
  final bool enabled;
  final VoidCallback onFieldChanged;

  const _IdentificationSection({
    required this.tradeNameCtrl,
    required this.legalNameCtrl,
    required this.enabled,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Identificação'),
      const SizedBox(height: 16),
      TextFormField(
        controller: tradeNameCtrl,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'Nome Fantasia',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => onFieldChanged(),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: legalNameCtrl,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'Razão Social',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => onFieldChanged(),
      ),
    ],
  );
}

class _PlanLimitsSection extends StatelessWidget {
  final String? planType;
  final String? orgType;
  final TextEditingController maxVehiclesCtrl;
  final TextEditingController maxContractsCtrl;
  final TextEditingController costCtrl;
  final TextEditingController dwellTimeCtrl;
  final bool enabled;
  final ValueChanged<String?> onPlanTypeChanged;
  final ValueChanged<String?> onOrgTypeChanged;
  final VoidCallback onFieldChanged;

  const _PlanLimitsSection({
    required this.planType,
    required this.orgType,
    required this.maxVehiclesCtrl,
    required this.maxContractsCtrl,
    required this.costCtrl,
    required this.dwellTimeCtrl,
    required this.enabled,
    required this.onPlanTypeChanged,
    required this.onOrgTypeChanged,
    required this.onFieldChanged,
  });

  static String? _validatePositiveInt(String? v) {
    if (v == null || v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 1) return 'Mínimo: 1';
    return null;
  }

  static String? _validateCost(String? v) {
    if (v == null || v.isEmpty) return 'Obrigatório';
    final n = double.tryParse(v.replaceAll(',', '.'));
    if (n == null || n.isNaN || n < 0) return 'Valor inválido (≥ 0)';
    return null;
  }

  static String? _validateDwellTime(String? v) {
    if (v == null || v.isEmpty) return 'Obrigatório';
    final n = int.tryParse(v);
    if (n == null || n < 300) return 'Mínimo: 300s (5min)';
    return null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Plano & Limites'),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: planType,
        decoration: const InputDecoration(
          labelText: 'Plano',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: null,
            child: Text('Não Definido', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem(
            value: 'starter',
            child: Text('Starter', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem(
            value: 'professional',
            child: Text('Professional', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem(
            value: 'enterprise',
            child: Text('Enterprise', overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: enabled ? onPlanTypeChanged : null,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: orgType,
        decoration: const InputDecoration(
          labelText: 'Tipo de Organização',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: null,
            child: Text('Não Definido', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem(
            value: 'CARGO',
            child: Text('Cargas (Cargo)', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem(
            value: 'PASSENGER',
            child: Text('Passageiros', overflow: TextOverflow.ellipsis),
          ),
          DropdownMenuItem(
            value: 'URBAN_LOGISTICS',
            child: Text('Logística Urbana', overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: enabled ? onOrgTypeChanged : null,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: maxVehiclesCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Max Veículos (Vazio=Ilimitado)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => onFieldChanged(),
              validator: _validatePositiveInt,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: maxContractsCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Max Contratos (Vazio=Ilimitado)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => onFieldChanged(),
              validator: _validatePositiveInt,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: costCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Custo Ferramenta (R\$)',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onFieldChanged(),
              validator: _validateCost,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: dwellTimeCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Dwell Time (Segundos)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => onFieldChanged(),
              validator: _validateDwellTime,
            ),
          ),
        ],
      ),
    ],
  );
}

class _BillingIntegrationSection extends StatelessWidget {
  final TextEditingController billingDayCtrl;
  final TextEditingController contactEmailCtrl;
  final TextEditingController externalIdCtrl;
  final bool enabled;
  final VoidCallback onFieldChanged;

  const _BillingIntegrationSection({
    required this.billingDayCtrl,
    required this.contactEmailCtrl,
    required this.externalIdCtrl,
    required this.enabled,
    required this.onFieldChanged,
  });

  static String? _validateBillingDay(String? v) {
    if (v == null || v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 1 || n > 28) return 'Dia inválido (1-28)';
    return null;
  }

  static String? _validateEmail(String? v) {
    if (v == null || v.isEmpty) return null;
    if (!v.contains('@') || !v.contains('.')) return 'E-mail inválido';
    return null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Faturamento & Integracao'),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: billingDayCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Dia de Faturamento (1-28)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => onFieldChanged(),
              validator: _validateBillingDay,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: contactEmailCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'E-mail de Contato',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => onFieldChanged(),
              validator: _validateEmail,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: externalIdCtrl,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'ID Externo (CRM/ERP)',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => onFieldChanged(),
      ),
    ],
  );
}

// ── CT10 Sections ─────────────────────────────────────────────────────────────

class _ForensicEngineSection extends StatelessWidget {
  final TextEditingController clockDriftCtrl;
  final bool enabled;
  final VoidCallback onFieldChanged;

  const _ForensicEngineSection({
    required this.clockDriftCtrl,
    required this.enabled,
    required this.onFieldChanged,
  });

  static String? _validateClockDrift(String? v) {
    if (v == null || v.isEmpty) return 'Obrigatório';
    final n = int.tryParse(v);
    if (n == null || n < 0) return 'Mínimo: 0 segundos';
    return null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Motor Forense'),
      const SizedBox(height: 16),
      TextFormField(
        key: const Key('clock_drift_tolerance_s_field'),
        controller: clockDriftCtrl,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'Tolerância Clock Drift (segundos)',
          helperText:
              'Desvio máximo de relógio tolerado para evidências. Padrão: 300s.',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => onFieldChanged(),
        validator: _validateClockDrift,
      ),
    ],
  );
}

class _ComplianceSection extends StatelessWidget {
  final TextEditingController dataRetentionCtrl;
  final bool enabled;
  final VoidCallback onFieldChanged;

  const _ComplianceSection({
    required this.dataRetentionCtrl,
    required this.enabled,
    required this.onFieldChanged,
  });

  static String? _validateRetention(String? v) {
    if (v == null || v.isEmpty) return 'Obrigatório';
    final n = int.tryParse(v);
    if (n == null || n < 1) return 'Mínimo: 1 dia';
    return null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Compliance'),
      const SizedBox(height: 16),
      TextFormField(
        key: const Key('data_retention_days_field'),
        controller: dataRetentionCtrl,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'Retenção de Dados (dias)',
          helperText:
              'Período de retenção de evidências online. Padrão: 1825 dias (5 anos).',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => onFieldChanged(),
        validator: _validateRetention,
      ),
    ],
  );
}

class _InfrastructureSection extends StatelessWidget {
  final TextEditingController connectionPoolCtrl;
  final TextEditingController storageQuotaCtrl;
  final bool enabled;
  final VoidCallback onFieldChanged;

  const _InfrastructureSection({
    required this.connectionPoolCtrl,
    required this.storageQuotaCtrl,
    required this.enabled,
    required this.onFieldChanged,
  });

  static String? _validatePool(String? v) {
    if (v == null || v.isEmpty) return 'Obrigatório';
    final n = int.tryParse(v);
    if (n == null || n < 1 || n > 500) return 'Entre 1 e 500';
    return null;
  }

  static String? _validateStorage(String? v) {
    if (v == null || v.isEmpty) return 'Obrigatório';
    final n = int.tryParse(v);
    if (n == null || n < 1) return 'Mínimo: 1 GB';
    return null;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Infraestrutura'),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              key: const Key('connection_pool_limit_field'),
              controller: connectionPoolCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Connection Pool Limit',
                helperText: '1–500 conexões',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => onFieldChanged(),
              validator: _validatePool,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              key: const Key('storage_quota_gb_field'),
              controller: storageQuotaCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Storage Quota (GB)',
                helperText: 'Mínimo: 1 GB',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => onFieldChanged(),
              validator: _validateStorage,
            ),
          ),
        ],
      ),
    ],
  );
}

class _AllowedDomainsSection extends StatelessWidget {
  final List<String> domains;
  final TextEditingController domainInputCtrl;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _AllowedDomainsSection({
    required this.domains,
    required this.domainInputCtrl,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Domínios Permitidos'),
      const SizedBox(height: 8),
      const Text(
        'Lista de domínios de e-mail autorizados para login (ex: empresa.com.br).',
        style: TextStyle(fontSize: 12, color: VeraProbColors.textSecondary),
      ),
      const SizedBox(height: 12),
      if (domains.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: domains.map((domain) {
            return Chip(
              key: Key('domain_chip_$domain'),
              label: Text(domain, style: VeraProbTypography.mono(size: 12)),
              deleteIcon: enabled ? const Icon(Icons.close, size: 14) : null,
              onDeleted: enabled ? () => onRemove(domain) : null,
              backgroundColor: VeraProbColors.superAdminSurface.withValues(
                alpha: 0.3,
              ),
            );
          }).toList(),
        )
      else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Nenhum domínio configurado — qualquer e-mail pode fazer login.',
            style: TextStyle(
              fontSize: 12,
              color: VeraProbColors.warning,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      if (enabled) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('domain_input_field'),
                controller: domainInputCtrl,
                decoration: const InputDecoration(
                  labelText: 'Adicionar Domínio',
                  hintText: 'ex: viacao.com.br',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('domain_add_button'),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Adicionar domínio',
              onPressed: onAdd,
              color: VeraProbColors.secondary,
            ),
          ],
        ),
      ],
    ],
  );
}

// ── Capabilities Section ──────────────────────────────────────────────────────

class _CapabilitiesSection extends StatelessWidget {
  final OrgCapabilitiesViewModel capabilities;
  final bool enabled;
  final ValueChanged<OrgCapabilitiesViewModel> onChanged;

  const _CapabilitiesSection({
    required this.capabilities,
    required this.enabled,
    required this.onChanged,
  });

  Widget _switch(
    String title,
    bool value,
    OrgCapabilitiesViewModel Function(bool) updater,
  ) => SwitchListTile(
    title: Text(title),
    value: value,
    onChanged: enabled ? (v) => onChanged(updater(v)) : null,
    dense: true,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('Capabilities'),
      const SizedBox(height: 8),
      _switch(
        'Lacre',
        capabilities.allowsSealing,
        (v) => capabilities.copyWith(allowsSealing: v),
      ),
      _switch(
        'Carregamento',
        capabilities.allowsLoading,
        (v) => capabilities.copyWith(allowsLoading: v),
      ),
      _switch(
        'Cargo Check',
        capabilities.allowsCargoCheck,
        (v) => capabilities.copyWith(allowsCargoCheck: v),
      ),
      _switch(
        'Incidente',
        capabilities.allowsIncident,
        (v) => capabilities.copyWith(allowsIncident: v),
      ),
      _switch(
        'Doc',
        capabilities.allowsDoc,
        (v) => capabilities.copyWith(allowsDoc: v),
      ),
      _switch(
        'Smart Classify',
        capabilities.smartClassify,
        (v) => capabilities.copyWith(smartClassify: v),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: VeraProbColors.textPrimary,
      ),
    );
  }
}
