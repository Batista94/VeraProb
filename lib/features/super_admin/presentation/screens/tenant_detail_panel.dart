import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/update_quota_form_data.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_health_card.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_secret_card.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Right panel: detail view for a selected tenant organization.
///
/// Stage H: Split-view layout — this panel fills the remaining space.
/// Tabs: Métricas (Health Cards), Configuração, Segurança.
class TenantDetailPanel extends ConsumerStatefulWidget {
  final TenantHealthView tenant;

  const TenantDetailPanel({super.key, required this.tenant});

  @override
  ConsumerState<TenantDetailPanel> createState() => _TenantDetailPanelState();
}

class _TenantDetailPanelState extends ConsumerState<TenantDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _archiveOrg(TenantHealthView t) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ArchiveConfirmationDialog(),
    );
    if (reason == null || !mounted) return;

    try {
      final handler = ref.read(archiveOrganizationHandlerProvider);
      final userId =
          ref.read(authStateProvider).valueOrNull?.session?.user.id ?? '';
      final sessionId = ref.read(currentSessionIdProvider) ?? '';
      await handler.handlePrimitives(
        orgId: t.id,
        reason: reason,
        superAdminUserId: userId,
        currentStatusKey: t.statusKey,
        sessionId: sessionId,
      );

      ref.invalidate(tenantHealthSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organização arquivada com sucesso.')),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao arquivar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _unarchiveOrg(TenantHealthView t) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonConfirmationDialog(),
    );
    if (reason == null || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final userId =
          ref.read(authStateProvider).valueOrNull?.session?.user.id ?? '';
      await repo.unarchiveOrganization(
        orgId: t.id,
        reason: reason,
        superAdminId: userId,
      );

      ref.invalidate(tenantHealthSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Organização desarquivada com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao desarquivar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tenant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (t.legalName != null)
                      Text(
                        t.legalName!,
                        style: const TextStyle(
                          color: VeraProbColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              _OrgStatusBadge(label: t.status?.label),
              const SizedBox(width: 8),
              _PlanBadge(planType: t.planType),
              if (t.isOperational) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _archiveOrg(t),
                  icon: const Icon(Icons.archive_outlined, size: 16),
                  label: const Text('Arquivar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VeraProbColors.warning,
                    side: const BorderSide(color: VeraProbColors.warning),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (t.isArchived) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _unarchiveOrg(t),
                  icon: const Icon(Icons.unarchive_outlined, size: 16),
                  label: const Text('Desarquivar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: VeraProbColors.success,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            t.id,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: VeraProbColors.textDisabled,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Tabs ───────────────────────────────────────────────────
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: VeraProbColors.secondary,
          unselectedLabelColor: VeraProbColors.textSecondary,
          indicatorColor: VeraProbColors.secondary,
          tabs: const [
            Tab(text: 'Métricas'),
            Tab(text: 'Configuração'),
            Tab(text: 'Segurança'),
            Tab(text: 'Usuários'),
          ],
        ),
        const Divider(height: 1),

        // ── Tab content ────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _MetricsTab(tenant: t),
              _ConfigTab(tenant: t),
              _SecurityTab(tenant: t),
              _UsersTab(tenant: t),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tabs ─────────────────────────────────────────────────────────────────────

class _MetricsTab extends StatelessWidget {
  final TenantHealthView tenant;
  const _MetricsTab({required this.tenant});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Contratos Ativos',
              value: '${tenant.activeContractCount}',
              icon: Icons.description_outlined,
              valueColor: tenant.activeContractCount > 0
                  ? VeraProbColors.success
                  : VeraProbColors.textSecondary,
            ),
          ),
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Limite de Veículos',
              value: tenant.maxVehicles == 0
                  ? 'Ilimitado'
                  : '${tenant.maxVehicles}',
              icon: Icons.local_shipping_outlined,
            ),
          ),
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Última Telemetria',
              value: tenant.lastTelemetryAt != null
                  ? _formatDateTime(tenant.lastTelemetryAt!)
                  : 'Nunca',
              icon: Icons.satellite_alt_outlined,
              valueColor: tenant.lastTelemetryAt == null
                  ? VeraProbColors.textDisabled
                  : null,
            ),
          ),
          SizedBox(
            width: 240,
            child: OrgHealthCard(
              title: 'Alertas Críticos',
              value: '${tenant.openCriticalAlertCount}',
              icon: Icons.warning_amber_outlined,
              valueColor: tenant.hasCriticalAlerts
                  ? VeraProbColors.error
                  : VeraProbColors.success,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ConfigTab extends ConsumerStatefulWidget {
  final TenantHealthView tenant;
  const _ConfigTab({required this.tenant});

  @override
  ConsumerState<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<_ConfigTab> {
  late OrgCapabilitiesViewModel _capabilities;
  final _formKey = GlobalKey<FormState>();

  String? _planType;
  String? _orgType;
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
    _maxVehiclesCtrl.text = t.maxVehicles == 0 ? '' : t.maxVehicles.toString();
    _maxContractsCtrl.text = t.maxActiveContracts == 0
        ? ''
        : t.maxActiveContracts.toString();
    _costCtrl.text = t.toolCostCents != null
        ? (t.toolCostCents! / 100).toStringAsFixed(2)
        : '';
    _dwellTimeCtrl.text = t.dwellTimeSeconds.toString();
    _billingDayCtrl.text = t.billingDay?.toString() ?? '';
    _contactEmailCtrl.text = t.contactEmail ?? '';
    _externalIdCtrl.text = t.externalId ?? '';
  }

  @override
  void didUpdateWidget(covariant _ConfigTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenant.id != widget.tenant.id ||
        oldWidget.tenant != widget.tenant) {
      _initValues(widget.tenant);
    }
  }

  @override
  void dispose() {
    _maxVehiclesCtrl.dispose();
    _maxContractsCtrl.dispose();
    _costCtrl.dispose();
    _dwellTimeCtrl.dispose();
    _billingDayCtrl.dispose();
    _contactEmailCtrl.dispose();
    _externalIdCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final t = widget.tenant;
    final costStr = t.toolCostCents != null
        ? (t.toolCostCents! / 100).toStringAsFixed(2)
        : '';
    final mvStr = t.maxVehicles == 0 ? '' : t.maxVehicles.toString();
    final mcStr = t.maxActiveContracts == 0
        ? ''
        : t.maxActiveContracts.toString();

    return _capabilities != t.capabilities ||
        _planType != t.planType ||
        _orgType != t.organizationType ||
        _maxVehiclesCtrl.text != mvStr ||
        _maxContractsCtrl.text != mcStr ||
        _costCtrl.text != costStr ||
        _dwellTimeCtrl.text != t.dwellTimeSeconds.toString() ||
        _billingDayCtrl.text != (t.billingDay?.toString() ?? '') ||
        _contactEmailCtrl.text != (t.contactEmail ?? '') ||
        _externalIdCtrl.text != (t.externalId ?? '');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonConfirmationDialog(),
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
            ref.read(authStateProvider).valueOrNull?.session?.user.id ?? '',
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
      ).toCommand();

      await ref.read(updateOrganizationQuotaHandlerProvider).handle(cmd);
      ref.invalidate(tenantHealthSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações atualizadas com sucesso.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Plano & Limites'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _planType,
              decoration: const InputDecoration(
                labelText: 'Plano',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'starter', child: Text('Starter')),
                DropdownMenuItem(
                  value: 'professional',
                  child: Text('Professional'),
                ),
                DropdownMenuItem(
                  value: 'enterprise',
                  child: Text('Enterprise'),
                ),
              ],
              onChanged: (v) => setState(() => _planType = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _orgType,
              decoration: const InputDecoration(
                labelText: 'Tipo de Organização',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Não Definido')),
                DropdownMenuItem(value: 'CARGO', child: Text('Cargas (Cargo)')),
                DropdownMenuItem(
                  value: 'PASSENGER',
                  child: Text('Passageiros'),
                ),
                DropdownMenuItem(
                  value: 'URBAN_LOGISTICS',
                  child: Text('Logística Urbana'),
                ),
              ],
              onChanged: (v) => setState(() => _orgType = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _maxVehiclesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max Veículos (Vazio=Ilimitado)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _maxContractsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Max Contratos (Vazio=Ilimitado)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _costCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Custo Ferramenta (R\$)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _dwellTimeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dwell Time (Segundos)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionTitle('Faturamento & Integracao'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _billingDayCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Dia de Faturamento (1-28)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _contactEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'E-mail de Contato',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _externalIdCtrl,
              decoration: const InputDecoration(
                labelText: 'ID Externo (CRM/ERP)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            const _SectionTitle('Capabilities'),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Lacre'),
              value: _capabilities.allowsSealing,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsSealing: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Carregamento'),
              value: _capabilities.allowsLoading,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsLoading: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Cargo Check'),
              value: _capabilities.allowsCargoCheck,
              onChanged: (v) => setState(
                () =>
                    _capabilities = _capabilities.copyWith(allowsCargoCheck: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Incidente'),
              value: _capabilities.allowsIncident,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsIncident: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Doc'),
              value: _capabilities.allowsDoc,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(allowsDoc: v),
              ),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Smart Classify'),
              value: _capabilities.smartClassify,
              onChanged: (v) => setState(
                () => _capabilities = _capabilities.copyWith(smartClassify: v),
              ),
              dense: true,
            ),
            if (_isDirty) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _save,
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

/// Confirmation dialog requiring a reason (min 10 chars) before saving.
class _ReasonConfirmationDialog extends StatefulWidget {
  const _ReasonConfirmationDialog();

  @override
  State<_ReasonConfirmationDialog> createState() =>
      _ReasonConfirmationDialogState();
}

class _ReasonConfirmationDialogState extends State<_ReasonConfirmationDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _isValid => _reasonCtrl.text.trim().length >= 10;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Justificativa'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Informe o motivo da alteracao de capabilities. '
              'Este registro sera gravado no log de auditoria.',
              style: TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo *',
                hintText: 'Minimo 10 caracteres',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_reasonCtrl.text.trim())
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _SecurityTab extends StatelessWidget {
  final TenantHealthView tenant;
  const _SecurityTab({required this.tenant});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OrgSecretCard(
            organizationId: tenant.id,
            organizationName: tenant.name,
          ),
        ],
      ),
    );
  }
}

// ── Dialogs ───────────────────────────────────────────────────────────────────

class _ArchiveConfirmationDialog extends StatefulWidget {
  const _ArchiveConfirmationDialog();

  @override
  State<_ArchiveConfirmationDialog> createState() =>
      _ArchiveConfirmationDialogState();
}

class _ArchiveConfirmationDialogState
    extends State<_ArchiveConfirmationDialog> {
  final _reasonCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.archive_outlined, color: VeraProbColors.warning, size: 20),
          SizedBox(width: 8),
          Text('Arquivar Organização'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta ação irá arquivar a organização. Todos os segredos de API '
                'serão revogados imediatamente. A organização não poderá mais '
                'receber telemetria ou gerar novos contratos.',
                style: TextStyle(
                  fontSize: 13,
                  color: VeraProbColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  hintText: 'Mínimo 10 caracteres',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (v) {
                  final val = v?.trim() ?? '';
                  if (val.isEmpty) return 'Motivo obrigatório.';
                  if (val.length < 10) return 'Mínimo 10 caracteres.';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: VeraProbColors.warning,
          ),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_reasonCtrl.text.trim());
            }
          },
          child: const Text('Confirmar Arquivamento'),
        ),
      ],
    );
  }
}

// ── Shared helper widgets ─────────────────────────────────────────────────────

/// Multi-status badge replacing the old boolean _StatusBadge.
///
/// Uses [label] string from [OrgStatus.label] — no domain import needed.
class _OrgStatusBadge extends StatelessWidget {
  final String? label;
  const _OrgStatusBadge({this.label});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _resolve(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label ?? '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData?) _resolve(String? lbl) {
    switch (lbl) {
      case 'Ativo':
        return (VeraProbColors.success, null);
      case 'Trial':
        return (VeraProbColors.info, null);
      case 'Suspenso':
        return (VeraProbColors.delayed, Icons.pause_circle_outline);
      case 'Churned':
        return (VeraProbColors.warning, Icons.cancel_outlined);
      case 'Arquivado':
        return (Colors.amber, Icons.lock_outline);
      case 'Excluído':
        return (VeraProbColors.error, Icons.delete_outline);
      default:
        return (VeraProbColors.textSecondary, null);
    }
  }
}

class _PlanBadge extends StatelessWidget {
  final String? planType;
  const _PlanBadge({this.planType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VeraProbColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        planType?.toUpperCase() ?? '—',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: VeraProbColors.secondary,
        ),
      ),
    );
  }
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

class _UsersTab extends ConsumerStatefulWidget {
  final TenantHealthView tenant;
  const _UsersTab({required this.tenant});

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  List<Map<String, dynamic>>? _members;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final members = await repo.getTenantMembers(widget.tenant.id);
      if (mounted) {
        setState(() {
          _members = members;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleStatus(String userId, bool currentStatus) async {
    try {
      final repo = ref.read(superAdminRepositoryProvider);
      await repo.toggleTenantMemberStatus(
        orgId: widget.tenant.id,
        userId: userId,
        isActive: !currentStatus,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              currentStatus ? 'Usuário inativado.' : 'Usuário reativado.',
            ),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
      await _loadMembers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _resendInvite(String email) async {
    try {
      final repo = ref.read(superAdminRepositoryProvider);
      await repo.resendInvitation(email: email, orgName: widget.tenant.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Convite reenviado.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reenviar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  Future<void> _addAdmin() async {
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Adicionar Administrador'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: TextFormField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'E-mail do Administrador',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'E-mail obrigatório.';
                final emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-z]{2,}');
                if (!emailRegex.hasMatch(v.trim())) return 'E-mail inválido.';
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Convidar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final repo = ref.read(superAdminRepositoryProvider);
      final userId =
          ref.read(authStateProvider).valueOrNull?.session?.user.id ?? '';
      const uuid = Uuid();
      await repo.addAdminToOrganization(
        orgId: widget.tenant.id,
        email: emailCtrl.text.trim(),
        invitationId: uuid.v4(),
        token: uuid.v4(),
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(days: 7)),
        superAdminUserId: userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Convite enviado para ${emailCtrl.text.trim()}.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
      await _loadMembers();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header: Adicionar Admin button ──────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Administradores',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: _addAdmin,
                icon: const Icon(Icons.person_add_outlined, size: 16),
                label: const Text('Adicionar Administrador'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Content ────────────────────────────────────────
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Erro ao carregar usuários',
              style: TextStyle(color: VeraProbColors.error),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadMembers,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }
    if (_members == null || _members!.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum usuário ou convite pendente encontrado.\nUse o botão acima para adicionar um administrador.',
          textAlign: TextAlign.center,
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: _members!.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final m = _members![index];
        final bool isActive = m['is_active'] as bool? ?? false;
        final String email = m['email'] as String? ?? '';
        final String role = m['role'] as String? ?? '';
        final String status = m['status'] as String? ?? 'inactive';
        final hasSignedIn = m['last_sign_in'] != null;
        final bool isPending = status == 'pending';
        final userId = m['user_id'] as String?;

        return ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: isPending
                ? VeraProbColors.warning.withValues(alpha: 0.15)
                : isActive
                ? VeraProbColors.success.withValues(alpha: 0.15)
                : VeraProbColors.error.withValues(alpha: 0.1),
            child: Icon(
              isPending
                  ? Icons.schedule_outlined
                  : isActive
                  ? Icons.person_outlined
                  : Icons.person_off_outlined,
              size: 16,
              color: isPending
                  ? VeraProbColors.warning
                  : isActive
                  ? VeraProbColors.success
                  : VeraProbColors.error,
            ),
          ),
          title: Row(
            children: [
              Flexible(child: Text(email, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              _StatusChip(status: status),
            ],
          ),
          subtitle: Text(
            'Role: $role | Login: ${hasSignedIn ? 'Sim' : 'Nunca'}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reenviar convite: para pendentes ou quem nunca logou
              if (isPending || !hasSignedIn)
                IconButton(
                  icon: const Icon(Icons.send_outlined, size: 18),
                  tooltip: 'Reenviar Convite',
                  onPressed: () => _resendInvite(email),
                ),
              // Ativar/Inativar: apenas para membros já registrados
              if (!isPending && userId != null)
                IconButton(
                  icon: Icon(
                    isActive ? Icons.block : Icons.check_circle_outline,
                    size: 18,
                  ),
                  tooltip: isActive ? 'Inativar Usuário' : 'Reativar Usuário',
                  color: isActive
                      ? VeraProbColors.error
                      : VeraProbColors.success,
                  onPressed: () => _toggleStatus(userId, isActive),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('Ativo', VeraProbColors.success),
      'pending' => ('Pendente', VeraProbColors.warning),
      _ => ('Inativo', VeraProbColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
