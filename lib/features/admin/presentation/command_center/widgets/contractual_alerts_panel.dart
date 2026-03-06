import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../domain/sla_audit/operational_alert.dart';
import '../../../../../state/providers/alert_providers.dart';
import '../../screens/widgets/investigation_modal.dart';

/// OCC panel displaying contractual operational alerts for triage.
///
/// Sorted by severity (CRITICAL → HIGH → WARNING), then by time.
/// Strictly read-only — lifecycle actions delegate to AlertService.
class ContractualAlertsPanel extends ConsumerWidget {
  const ContractualAlertsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(activeAlertsProvider);

    return Container(
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BusFlowColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: BusFlowColors.border.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: BusFlowColors.critical,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Alertas Contratuais',
                  style: BusFlowTypography.sectionTitle.copyWith(
                    color: BusFlowColors.textPrimary,
                  ),
                ),
                const Spacer(),
                alertsAsync.when(
                  data: (alerts) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: alerts.isNotEmpty
                          ? BusFlowColors.critical.withValues(alpha: 0.2)
                          : BusFlowColors.onTime.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${alerts.length}',
                      style: TextStyle(
                        color: alerts.isNotEmpty
                            ? BusFlowColors.critical
                            : BusFlowColors.onTime,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  loading: () => const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (error, _) => const Icon(
                    Icons.error_outline,
                    color: BusFlowColors.critical,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),

          // ── Alert List ────────────────────────────────
          Expanded(
            child: alertsAsync.when(
              data: (alerts) {
                if (alerts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 48,
                          color: BusFlowColors.onTime.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhum alerta ativo',
                          style: BusFlowTypography.bodyMedium.copyWith(
                            color: BusFlowColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: alerts.length,
                  itemBuilder: (context, index) {
                    return _AlertCard(alert: alerts[index]);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Erro ao carregar alertas',
                  style: BusFlowTypography.bodyMedium.copyWith(
                    color: BusFlowColors.critical,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alert Card ─────────────────────────────────────────────

class _AlertCard extends ConsumerWidget {
  final OperationalAlert alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severityColor = _severityColor(alert.severity);
    final formatter = DateFormat('dd/MM HH:mm');

    return Card(
      color: BusFlowColors.background,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: severityColor.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          // Navigate to InvestigationModal for full causal chain
          showDialog(
            context: context,
            builder: (_) => InvestigationModal(
              setId: alert.entityId,
              contractId: alert.contractId,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: severity badge + type + time
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      alert.severity,
                      style: TextStyle(
                        color: severityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _alertTypeLabel(alert.alertType),
                      style: BusFlowTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: BusFlowColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    formatter.format(alert.triggeredAtUtc.toLocal()),
                    style: TextStyle(
                      color: BusFlowColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Details row
              Row(
                children: [
                  Icon(
                    Icons.route,
                    size: 14,
                    color: BusFlowColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    alert.entityId,
                    style: TextStyle(
                      color: BusFlowColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: BusFlowColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      alert.contractId,
                      style: TextStyle(
                        color: BusFlowColors.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Action row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => InvestigationModal(
                          setId: alert.entityId,
                          contractId: alert.contractId,
                        ),
                      );
                    },
                    icon: const Icon(Icons.search, size: 14),
                    label: const Text('Investigar'),
                    style: TextButton.styleFrom(
                      foregroundColor: BusFlowColors.secondary,
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final service = ref.read(alertServiceProvider);
                      await service.acknowledge(
                        alertId: alert.id,
                        userId: 'operator', // From auth context in production
                        atUtc: DateTime.now().toUtc(),
                      );
                      ref.invalidate(activeAlertsProvider);
                    },
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Confirmar'),
                    style: TextButton.styleFrom(
                      foregroundColor: BusFlowColors.onTime,
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'CRITICAL':
        return BusFlowColors.critical;
      case 'HIGH':
        return BusFlowColors.delayed;
      case 'WARNING':
        return Colors.orange;
      default:
        return BusFlowColors.textSecondary;
    }
  }

  String _alertTypeLabel(String alertType) {
    switch (alertType) {
      case 'NO_SHOW':
        return 'Não Comparecimento';
      case 'EVIDENCE_GAP':
        return 'Lacuna de Evidência';
      case 'PENALTY_APPLIED':
        return 'Penalidade Aplicada';
      default:
        return alertType;
    }
  }
}
