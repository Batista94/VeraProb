import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/state/providers/sla_providers.dart';
import 'package:busflow/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:busflow/domain/sla_audit/execution_status.dart';
import 'widgets/_sla_execution_detail_drawer.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

class SlaAuditScreen extends ConsumerWidget {
  const SlaAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: BusFlowColors.background,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auditoria de SLA',
              style: BusFlowTypography.sectionTitle.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 24),
            const _SlaSummarySection(),
            const SizedBox(height: 32),
            const Expanded(child: _SlaExceptionsTable()),
          ],
        ),
      ),
    );
  }
}

class _SlaSummarySection extends ConsumerWidget {
  const _SlaSummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(slaSummaryProvider);

    return summaryAsync.when(
      data: (summary) => Row(
        children: [
          Expanded(
            child: _SummaryCard(
              title: 'Executados',
              value: summary.totalExecuted,
              color: BusFlowColors.success,
              percentage: summary.total > 0
                  ? (summary.totalExecuted / summary.total * 100).round()
                  : 0,
              revenueLabel: 'Receita Protegida',
              revenueValue: summary.protectedRevenue,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _SummaryCard(
              title: 'Em Risco',
              value: summary.totalEvidenceGap,
              color: BusFlowColors.warning,
              percentage: summary.total > 0
                  ? (summary.totalEvidenceGap / summary.total * 100).round()
                  : 0,
              revenueLabel: 'Receita em Risco',
              revenueValue: summary.revenueAtRisk,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _SummaryCard(
              title: 'Perdidos',
              value: summary.totalNoShow,
              color: BusFlowColors.error,
              percentage: summary.total > 0
                  ? (summary.totalNoShow / summary.total * 100).round()
                  : 0,
              revenueLabel: 'Receita Perdida',
              revenueValue: summary.lostRevenue,
            ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Text('Erro ao carregar sumário: $err'),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final int value;
  final Color color;
  final int percentage;
  final String revenueLabel;
  final double revenueValue;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.percentage,
    required this.revenueLabel,
    required this.revenueValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BusFlowColors.border.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: BusFlowTypography.kpiLabel.copyWith(
              color: BusFlowColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value.toString(),
                style: BusFlowTypography.kpiValue.copyWith(
                  color: color,
                  fontSize: 36,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '$percentage%',
                  style: BusFlowTypography.bodySmall.copyWith(
                    color: BusFlowColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  revenueLabel,
                  style: BusFlowTypography.caption.copyWith(
                    color: BusFlowColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _currencyFormat.format(revenueValue),
                  style: BusFlowTypography.badge.copyWith(
                    color: color,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlaExceptionsTable extends ConsumerWidget {
  const _SlaExceptionsTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exceptionsAsync = ref.watch(slaExceptionsProvider);

    return exceptionsAsync.when(
      data: (exceptions) {
        if (exceptions.isEmpty) {
          return const Center(
            child: Text(
              'Nenhuma exceção detectada.',
              style: BusFlowTypography.bodyMedium,
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: BusFlowColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: BusFlowColors.border.withValues(alpha: 0.1),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  BusFlowColors.textPrimary.withValues(alpha: 0.05),
                ),
                columns: const [
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Janela')),
                  DataColumn(label: Text('Veículo Planejado')),
                  DataColumn(label: Text('Valor')),
                  DataColumn(label: Text('SET ID')),
                  DataColumn(label: Text('Ação')),
                ],
                rows: exceptions.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(_StatusBadge(status: item.status)),
                      DataCell(
                        Text(
                          '${_formatTime(item.windowStartUtc)} - ${_formatTime(item.windowEndUtc)}',
                          style: BusFlowTypography.bodyMedium,
                        ),
                      ),
                      DataCell(
                        Text(
                          item.plannedVehicleId ?? 'Any',
                          style: BusFlowTypography.bodyMedium,
                        ),
                      ),
                      DataCell(
                        Text(
                          _currencyFormat.format(item.contractualValue),
                          style: BusFlowTypography.bodyMedium,
                        ),
                      ),
                      DataCell(
                        Text(
                          '${item.setId.substring(0, 8)}...',
                          style: BusFlowTypography.bodyMedium,
                        ),
                      ),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.search, size: 20),
                          onPressed: () => _showDetail(context, item),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Text('Erro ao carregar exceções: $err'),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showDetail(BuildContext context, SlaExecutionItemView item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SlaExecutionDetailDrawer(item: item),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ExecutionStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == ExecutionStatus.noShow
        ? BusFlowColors.error
        : BusFlowColors.warning;

    final label = status == ExecutionStatus.noShow ? 'No Show' : 'Ev. Gap';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label.toUpperCase(),
        style: BusFlowTypography.badge.copyWith(color: color),
      ),
    );
  }
}
