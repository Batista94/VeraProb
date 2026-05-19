import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:intl/intl.dart';
import 'package:veraprob/application/shared/app_types.dart';
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
  }

  @override
  void didUpdateWidget(covariant TenantConfigTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-init only when switching tenant or when a committed snapshot arrives.
    // TenantHealthView has no value equality, so reference != is always true;
    // comparing id + updatedAt avoids clobbering in-progress edits on
    // unrelated parent rebuilds.
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant.updatedAt != widget.tenant.updatedAt) {
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
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _costString(int? cents) =>
      cents != null ? (cents / 100).toStringAsFixed(2) : '';

  bool get _isDisabled => widget.tenant.isArchived;

  bool get _capabilitiesChanged => _capabilities != widget.tenant.capabilities;

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
        _externalIdCtrl.text != (t.externalId ?? '');
  }

  bool get _isDirty => _capabilitiesChanged || _paramsChanged;

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

  Future<void> _copyToClipboard(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showSnackBar('Copiado para a área de transferência');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

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
        externalId: _externalIdCtrl.text.isEmpty ? null : _externalIdCtrl.text,
        organizationType: _orgType,
        tradeName: _tradeNameCtrl.text.isEmpty ? null : _tradeNameCtrl.text,
        legalName: _legalNameCtrl.text.isEmpty ? null : _legalNameCtrl.text,
        expectedUpdatedAt: t.updatedAt,
      ).toCommand();

      await ref.read(updateOrganizationQuotaHandlerProvider).handle(cmd);
      ref.invalidate(tenantHealthSnapshotProvider);
      await ref.read(tenantHealthSnapshotProvider.future);
      _showSnackBar(
        'Configurações atualizadas com sucesso.',
        backgroundColor: VeraProbColors.success,
      );
    } on ProviderException catch (e) {
      // Riverpod v3: unwrap ProviderException to get original error
      final original = e.exception;
      final msg = original is DomainException
          ? original.message
          : 'Erro: $original';
      _showSnackBar(msg, backgroundColor: VeraProbColors.error);
    } on DomainException catch (e) {
      _showSnackBar(e.message, backgroundColor: VeraProbColors.error);
    } catch (e) {
      _showSnackBar('Erro: $e', backgroundColor: VeraProbColors.error);
    }
  }

  List<Widget> _buildImmutableIdentitySection() {
    final createdAtStr = widget.tenant.createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(widget.tenant.createdAt!)
        : null;
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
      const SizedBox(height: 12),
      LockedFieldTile(
        label: 'Data de Criação',
        value: createdAtStr,
        placeholder: 'Não disponível',
        onCopy: createdAtStr != null
            ? () => _copyToClipboard(createdAtStr)
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
        initialValue: planType,
        decoration: const InputDecoration(
          labelText: 'Plano',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: null, child: Text('Não Definido')),
          DropdownMenuItem(value: 'starter', child: Text('Starter')),
          DropdownMenuItem(value: 'professional', child: Text('Professional')),
          DropdownMenuItem(value: 'enterprise', child: Text('Enterprise')),
        ],
        onChanged: enabled ? onPlanTypeChanged : null,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: orgType,
        decoration: const InputDecoration(
          labelText: 'Tipo de Organização',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: null, child: Text('Não Definido')),
          DropdownMenuItem(value: 'CARGO', child: Text('Cargas (Cargo)')),
          DropdownMenuItem(value: 'PASSENGER', child: Text('Passageiros')),
          DropdownMenuItem(
            value: 'URBAN_LOGISTICS',
            child: Text('Logística Urbana'),
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
