import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/super_admin/tenant_health_snapshot.dart';
import '../../../../infrastructure/providers/super_admin_providers.dart';

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
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
            Icon(Icons.business_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Nenhum tenant cadastrado.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
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
                  Colors.indigo.withValues(alpha: 0.08),
                ),
                columns: const [
                  DataColumn(label: Text('Organização')),
                  DataColumn(label: Text('Plano')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Contratos Ativos'), numeric: true),
                  DataColumn(label: Text('Limite Veículos'), numeric: true),
                  DataColumn(label: Text('Último Telemetria')),
                  DataColumn(label: Text('Alertas Críticos')),
                ],
                rows: tenants.map(_buildRow).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  DataRow _buildRow(TenantHealthSnapshot t) {
    return DataRow(
      cells: [
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (t.legalName != null)
                Text(
                  t.legalName!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
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
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              t.isActive ? 'Ativo' : 'Inativo',
              style: TextStyle(
                color: t.isActive ? Colors.green.shade700 : Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(Text('${t.activeContractCount}')),
        DataCell(Text('${t.maxVehicles}')),
        DataCell(
          Text(
            t.lastTelemetryAt != null
                ? _formatDateTime(t.lastTelemetryAt!)
                : '—',
            style: TextStyle(
              color: t.lastTelemetryAt == null ? Colors.grey : null,
            ),
          ),
        ),
        DataCell(
          t.hasCriticalAlerts
              ? Badge(
                  label: Text('${t.openCriticalAlertCount}'),
                  backgroundColor: Colors.red,
                  child: const Icon(
                    Icons.warning_amber,
                    color: Colors.red,
                    size: 20,
                  ),
                )
              : const Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 20),
        ),
      ],
    );
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
