import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../application/sla_audit/projections/dashboard_risk_feed_node.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/dashboard_risk_feed_provider.dart';
import '../../../../state/providers/sla_financial_providers.dart';
import '../screens/widgets/investigation_modal.dart';

final _timeFormat = DateFormat('HH:mm');

/// The new main dashboard component replacing the map heatmap.
/// Strictly a Read Model (CQRS) displaying high-level financial risk
/// and a severity-sorted feed of contractual executions.
class ContractualRiskRadar extends ConsumerWidget {
  const ContractualRiskRadar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        const _FinancialKpiRow(),
        const SizedBox(height: 32),
        const _RiskFeedList(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: BusFlowColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.radar, color: BusFlowColors.warning),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Radar de Risco Contratual', style: BusFlowTypography.kpiValue.copyWith(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              'Acompanhamento de SLA operacional e impacto financeiro',
              style: BusFlowTypography.bodyMedium.copyWith(
                color: BusFlowColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CFO KPIs
// ═══════════════════════════════════════════════════════════════

class _FinancialKpiRow extends ConsumerWidget {
  const _FinancialKpiRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final impactAsync = ref.watch(financialImpactProvider);

    return impactAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: BusFlowColors.primary),
      ),
      error: (err, _) => Text(
        'Erro ao carregar KPIs financeiros: $err',
        style: BusFlowTypography.bodySmall.copyWith(color: BusFlowColors.error),
      ),
      data: (impact) {
        return Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: 'Receita Protegida',
                value: 'R\$ ${(impact.protectedRevenue.cents / 100).toStringAsFixed(2)}',
                color: BusFlowColors.success,
                icon: Icons.shield,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _KpiCard(
                title: 'Receita em Risco (Atrasos)',
                value: 'R\$ ${(impact.revenueAtRisk.cents / 100).toStringAsFixed(2)}',
                color: BusFlowColors.warning,
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _KpiCard(
                title: 'SLA Violado (Penalty)',
                value: 'R\$ ${(impact.lostRevenue.cents / 100).toStringAsFixed(2)}',
                color: BusFlowColors.error,
                icon: Icons.gavel,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BusFlowColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: BusFlowTypography.caption.copyWith(
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: BusFlowTypography.kpiValue.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Timeline Feed
// ═══════════════════════════════════════════════════════════════

class _RiskFeedList extends ConsumerWidget {
  const _RiskFeedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(dashboardRiskFeedProvider);

    return Container(
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BusFlowColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.list_alt, size: 18, color: BusFlowColors.info),
                const SizedBox(width: 8),
                Text(
                  'Viagens Programadas (Turnos)',
                  style: BusFlowTypography.sectionTitle,
                ),
                const Spacer(),
                Text(
                  'Ordenado por Severidade',
                  style: BusFlowTypography.caption,
                ),
              ],
            ),
          ),
          feedAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: CircularProgressIndicator(color: BusFlowColors.primary),
              ),
            ),
            error: (err, _) => Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  'Erro ao carregar feed: $err',
                  style: BusFlowTypography.bodySmall.copyWith(
                    color: BusFlowColors.error,
                  ),
                ),
              ),
            ),
            data: (nodes) {
              if (nodes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'Nenhuma viagem programada para hoje',
                      style: BusFlowTypography.bodyMedium,
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                itemCount: nodes.length,
                itemBuilder: (context, index) {
                  return _FeedNodeItem(
                    node: nodes[index],
                    isLast: index == nodes.length - 1,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FeedNodeItem extends StatelessWidget {
  final DashboardRiskFeedNode node;
  final bool isLast;

  const _FeedNodeItem({required this.node, required this.isLast});

  Color _getSeverityColor() {
    switch (node.severity) {
      case DashboardFeedSeverity.critical:
        return BusFlowColors.error;
      case DashboardFeedSeverity.warning:
        return BusFlowColors.warning;
      case DashboardFeedSeverity.pending:
        return BusFlowColors.info;
      case DashboardFeedSeverity.onTime:
        return BusFlowColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getSeverityColor();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: node.severity == DashboardFeedSeverity.critical
                          ? BusFlowColors.error.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: BusFlowColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Event Content Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    // Open Investigation Modal for deep dive
                    showDialog(
                      context: context,
                      builder: (_) => InvestigationModal(
                        setId: node.execution.setId,
                        contractId: node.execution.contractId,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _timeFormat.format(node.execution.windowStartUtc.toLocal()),
                              style: BusFlowTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: BusFlowColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                node.execution.status.name.toUpperCase(),
                                style: BusFlowTypography.badge.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'SET ID: ${node.execution.setId.substring(0, 8)}...',
                          style: BusFlowTypography.caption.copyWith(
                            fontFamily: 'monospace',
                            color: BusFlowColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.attach_money,
                              size: 14,
                              color: BusFlowColors.textSecondary,
                            ),
                            Text(
                              'R\$ ${(node.execution.contractualValue.cents / 100).toStringAsFixed(2)}',
                              style: BusFlowTypography.bodySmall,
                            ),
                            if (node.activeAlerts.isNotEmpty) ...[
                              const Spacer(),
                              Icon(Icons.warning, size: 14, color: color),
                              const SizedBox(width: 4),
                              Text(
                                '${node.activeAlerts.length} ${node.activeAlerts.length == 1 ? 'Alerta' : 'Alertas'}',
                                style: BusFlowTypography.caption.copyWith(color: color),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
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
