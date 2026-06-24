import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/sla_audit/projections/dashboard_risk_feed_node.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/dashboard_risk_feed_provider.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_modal.dart';

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
        const FinancialKpiRow(),
        const SizedBox(height: 32),
        const RiskFeedList(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VeraProbColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.radar, color: VeraProbColors.warning),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Radar de Risco Contratual',
              style: VeraProbTypography.kpiValue.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              'Acompanhamento de SLA operacional e impacto financeiro',
              style: VeraProbTypography.bodyMedium.copyWith(
                color: VeraProbColors.textSecondary,
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

class FinancialKpiRow extends ConsumerWidget {
  const FinancialKpiRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final impactAsync = ref.watch(financialImpactProvider);
    final window = ref.watch(sparklineWindowProvider);
    final series = ref.watch(financialSparklineProvider(window)).asData?.value;
    // Provenance: every KPI is one tap from the raw impact ledger.
    void drillDown() => context.go(AdminNav.financialImpact.path);

    return switch (impactAsync) {
      AsyncLoading() => const Center(
        child: CircularProgressIndicator(color: VeraProbColors.primary),
      ),
      AsyncError(:final error) => Text(
        'Erro ao carregar KPIs financeiros: $error',
        style: VeraProbTypography.bodySmall.copyWith(
          color: VeraProbColors.error,
        ),
      ),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 7, label: Text('7d')),
              ButtonSegment<int>(value: 30, label: Text('30d')),
            ],
            selected: {window},
            onSelectionChanged: (s) =>
                ref.read(sparklineWindowProvider.notifier).set(s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Receita Protegida',
                  value:
                      'R\$ ${(value.protectedRevenue / 100).toStringAsFixed(2)}',
                  color: VeraProbColors.success,
                  icon: Icons.shield,
                  onTap: drillDown,
                  sparkline: series?.protectedCents,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'Receita em Risco (Atrasos)',
                  value:
                      'R\$ ${(value.revenueAtRisk / 100).toStringAsFixed(2)}',
                  color: VeraProbColors.warning,
                  icon: Icons.warning_amber_rounded,
                  onTap: drillDown,
                  sparkline: series?.atRiskCents,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _KpiCard(
                  title: 'SLA Violado (Penalty)',
                  value: 'R\$ ${(value.lostRevenue / 100).toStringAsFixed(2)}',
                  color: VeraProbColors.error,
                  icon: Icons.gavel,
                  onTap: drillDown,
                  sparkline: series?.lostCents,
                ),
              ),
            ],
          ),
        ],
      ),
    };
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final List<int>? sparkline;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
    this.sparkline,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$title: $value',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: VeraProbTypography.kpiLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onTap != null)
                      const Icon(
                        Icons.north_east_rounded,
                        size: 14,
                        color: VeraProbColors.textDisabled,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: VeraProbTypography.kpiValue.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sparkline != null && sparkline!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SparklineWidget(values: sparkline!, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Timeline Feed
// ═══════════════════════════════════════════════════════════════

class RiskFeedList extends ConsumerWidget {
  const RiskFeedList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(dashboardRiskFeedProvider);

    return Container(
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: VeraProbColors.border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.list_alt,
                  size: 18,
                  color: VeraProbColors.info,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Viagens Programadas (Turnos)',
                    style: VeraProbTypography.sectionTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Tooltip(
                  message: 'Ordenado por Severidade',
                  child: Icon(
                    Icons.sort_rounded,
                    size: 16,
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          switch (feedAsync) {
            AsyncLoading() => const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: CircularProgressIndicator(color: VeraProbColors.primary),
              ),
            ),
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(
                  'Erro ao carregar feed: $error',
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.error,
                  ),
                ),
              ),
            ),
            AsyncData(:final value) => () {
              if (value.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Text(
                      'Nenhuma viagem programada para hoje',
                      style: VeraProbTypography.bodyMedium,
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                itemCount: value.length,
                itemBuilder: (context, index) {
                  return _FeedNodeItem(
                    node: value[index],
                    isLast: index == value.length - 1,
                  );
                },
              );
            }(),
          },
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
        return VeraProbColors.error;
      case DashboardFeedSeverity.warning:
        return VeraProbColors.warning;
      case DashboardFeedSeverity.pending:
        return VeraProbColors.info;
      case DashboardFeedSeverity.onTime:
        return VeraProbColors.success;
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
                          ? VeraProbColors.error.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: VeraProbColors.border),
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
                    showDialog<void>(
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
                              _timeFormat.format(
                                node.execution.windowStartUtc.toLocal(),
                              ),
                              style: VeraProbTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: VeraProbColors.textPrimary,
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
                                style: VeraProbTypography.badge.copyWith(
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
                          style: VeraProbTypography.caption.copyWith(
                            fontFamily: 'monospace',
                            color: VeraProbColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.attach_money,
                              size: 14,
                              color: VeraProbColors.textSecondary,
                            ),
                            Text(
                              'R\$ ${(node.execution.contractualValue / 100).toStringAsFixed(2)}',
                              style: VeraProbTypography.bodySmall,
                            ),
                            if (node.activeAlerts.isNotEmpty) ...[
                              const Spacer(),
                              Icon(Icons.warning, size: 14, color: color),
                              const SizedBox(width: 4),
                              Text(
                                '${node.activeAlerts.length} ${node.activeAlerts.length == 1 ? 'Alerta' : 'Alertas'}',
                                style: VeraProbTypography.caption.copyWith(
                                  color: color,
                                ),
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
