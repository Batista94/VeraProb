import 'package:flutter/material.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_health_card.dart';

class TenantMetricsTab extends StatelessWidget {
  final TenantHealthView tenant;
  const TenantMetricsTab({super.key, required this.tenant});

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
