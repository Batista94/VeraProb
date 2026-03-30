import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/sla_audit/domain_exception.dart';
import '../../../../domain/super_admin/plan_type.dart';
import '../../../../domain/super_admin/tenant_health_snapshot.dart';
import '../../../../domain/super_admin/update_organization_quota_command.dart';
import '../../../../infrastructure/providers/super_admin_providers.dart';
import '../../../../state/providers/super_admin_auth_providers.dart';

/// Cross-tenant health dashboard for SuperAdmin.
///
/// Displays one row per organization with key health indicators.
/// Critical alert count shown with a red badge.
class TenantHealthPanel extends ConsumerWidget {
  const TenantHealthPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(tenantHealthSnapshotProvider);

    return snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: VeraProbColors.error,
            ),
            const SizedBox(height: 12),
            Text('Erro ao carregar tenants: $err'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(tenantHealthSnapshotProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
      data: (tenants) => _TenantTable(tenants: tenants, ref: ref),
    );
  }
}

class _TenantTable extends StatelessWidget {
  final List<TenantHealthSnapshot> tenants;
  final WidgetRef ref;

  const _TenantTable({required this.tenants, required this.ref});

  @override
  Widget build(BuildContext context) {
    if (tenants.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.business_outlined,
              size: 64,
              color: VeraProbColors.textDisabled,
            ),
            SizedBox(height: 16),
            Text(
              'Nenhum tenant cadastrado.',
              style: TextStyle(
                fontSize: 16,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Tenants (${tenants.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => ref.invalidate(tenantHealthSnapshotProvider),
                icon: const Icon(Icons.refresh),
                tooltip: 'Atualizar',
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  VeraProbColors.superAdminSurface.withValues(alpha: 0.3),
                ),
                columns: const [
                  DataColumn(label: Text('Organização')),
                  DataColumn(label: Text('Plano')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Contratos Ativos'), numeric: true),
                  DataColumn(label: Text('Veículos'), numeric: true),
                  DataColumn(label: Text('Último Telemetria')),
                  DataColumn(label: Text('Alertas Críticos')),
                  DataColumn(label: Text('Ações')),
                ],
                rows: tenants.map((t) => _buildRow(context, t)).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildRow(BuildContext context, TenantHealthSnapshot t) {
    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (t.legalName != null)
                Text(
                  t.legalName!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
            ],
          ),
        ),
        DataCell(Text(t.planType?.toUpperCase() ?? '—')),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: t.isActive
                  ? VeraProbColors.success.withValues(alpha: 0.15)
                  : VeraProbColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              t.isActive ? 'Ativo' : 'Inativo',
              style: TextStyle(
                color: t.isActive
                    ? VeraProbColors.success
                    : VeraProbColors.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            t.maxActiveContracts == 0
                ? '${t.activeContractCount}/∞'
                : '${t.activeContractCount}/${t.maxActiveContracts}',
            style: TextStyle(
              color: _quotaColor(t.activeContractCount, t.maxActiveContracts),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DataCell(Text(t.maxVehicles == 0 ? '∞' : '${t.maxVehicles}')),
        DataCell(
          Text(
            t.lastTelemetryAt != null
                ? _formatDateTime(t.lastTelemetryAt!)
                : '—',
            style: TextStyle(
              color: t.lastTelemetryAt == null
                  ? VeraProbColors.textDisabled
                  : null,
            ),
          ),
        ),
        DataCell(
          t.hasCriticalAlerts
              ? Badge(
                  label: Text('${t.openCriticalAlertCount}'),
                  backgroundColor: VeraProbColors.error,
                  child: const Icon(
                    Icons.warning_amber,
                    color: VeraProbColors.error,
                    size: 20,
                  ),
                )
              : const Icon(
                  Icons.check_circle_outline,
                  color: VeraProbColors.success,
                  size: 20,
                ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Editar cotas',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _EditQuotaDialog(snapshot: t),
            ),
          ),
        ),
      ],
    );
  }

  Color _quotaColor(int current, int max) {
    if (max == 0) return VeraProbColors.success;
    final ratio = current / max;
    if (ratio >= 1.0) return VeraProbColors.error;
    if (ratio >= 0.8) return Colors.orange;
    return VeraProbColors.success;
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Overlay modal for editing an organization's plan type and quota limits.
///
/// INV-24: Uses showDialog (overlay modal) for nested edit flows.
class _EditQuotaDialog extends ConsumerStatefulWidget {
  final TenantHealthSnapshot snapshot;

  const _EditQuotaDialog({required this.snapshot});

  @override
  ConsumerState<_EditQuotaDialog> createState() => _EditQuotaDialogState();
}

class _EditQuotaDialogState extends ConsumerState<_EditQuotaDialog> {
  late PlanType _selectedPlan;
  late final TextEditingController _maxVehiclesCtrl;
  late final TextEditingController _maxContractsCtrl;
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.snapshot.planType != null
        ? PlanType.fromDb(widget.snapshot.planType!)
        : PlanType.starter;
    _maxVehiclesCtrl = TextEditingController(
      text: widget.snapshot.maxVehicles == 0
          ? ''
          : '${widget.snapshot.maxVehicles}',
    );
    _maxContractsCtrl = TextEditingController(
      text: widget.snapshot.maxActiveContracts == 0
          ? ''
          : '${widget.snapshot.maxActiveContracts}',
    );
  }

  @override
  void dispose() {
    _maxVehiclesCtrl.dispose();
    _maxContractsCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _isEnterprise => _selectedPlan == PlanType.enterprise;

  Future<void> _submit() async {
    if (_isSaving) return;

    final int? maxVehicles = _isEnterprise
        ? null
        : int.tryParse(_maxVehiclesCtrl.text.trim());
    final int? maxContracts = _isEnterprise
        ? null
        : int.tryParse(_maxContractsCtrl.text.trim());

    if (!_isEnterprise && maxVehicles == null) {
      setState(() {
        _errorMessage = 'Informe um número válido para o limite de veículos.';
      });
      return;
    }
    if (!_isEnterprise && maxContracts == null) {
      setState(() {
        _errorMessage =
            'Informe um número válido para o limite de contratos ativos.';
      });
      return;
    }

    final superAdminId = ref.read(currentSuperAdminIdProvider);
    if (superAdminId == null) {
      setState(() {
        _errorMessage = 'Sessão inválida. Faça login novamente.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final cmd = UpdateOrganizationQuotaCommand(
      organizationId: widget.snapshot.id,
      newPlanType: _selectedPlan.dbValue,
      newMaxVehicles: maxVehicles,
      newMaxActiveContracts: maxContracts,
      superAdminUserId: superAdminId,
      reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
    );

    try {
      await ref.read(updateOrganizationQuotaHandlerProvider).handle(cmd);

      if (!mounted) return;
      ref.invalidate(tenantHealthSnapshotProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cotas de ${widget.snapshot.name} atualizadas com sucesso.',
          ),
          backgroundColor: VeraProbColors.success,
        ),
      );
    } on DomainException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isSaving = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Não foi possível atualizar as cotas. Tente novamente.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar Cotas — ${widget.snapshot.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<PlanType>(
              value: _selectedPlan,
              decoration: const InputDecoration(labelText: 'Plano'),
              items: PlanType.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (v) => setState(() => _selectedPlan = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxVehiclesCtrl,
              enabled: !_isEnterprise && !_isSaving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Limite de Veículos',
                hintText: _isEnterprise ? 'Ilimitado (enterprise)' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maxContractsCtrl,
              enabled: !_isEnterprise && !_isSaving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Limite de Contratos Ativos',
                hintText: _isEnterprise ? 'Ilimitado (enterprise)' : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              enabled: !_isSaving,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: VeraProbColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
