import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/state/providers/sla_financial_providers.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

class SlaFinancialImpactScreen extends ConsumerWidget {
  const SlaFinancialImpactScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final impactAsync = ref.watch(financialImpactProvider);

    return Container(
      color: BusFlowColors.background,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Impacto Financeiro do SLA',
              style: BusFlowTypography.sectionTitle.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Visão executiva de proteção de margem contratual',
              style: BusFlowTypography.bodySmall.copyWith(
                color: BusFlowColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: impactAsync.when(
                data: (impact) => _FinancialDashboard(
                  totalContractedRevenue: impact.totalContractedRevenue
                      .toDouble(),
                  protectedRevenue: impact.protectedRevenue.toDouble(),
                  revenueAtRisk: impact.revenueAtRisk.toDouble(),
                  lostRevenue: impact.lostRevenue.toDouble(),
                  riskPercentage: impact.riskPercentage,
                  lossPercentage: impact.lossPercentage,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: BusFlowColors.error,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Erro ao carregar impacto financeiro',
                        style: BusFlowTypography.bodyMedium.copyWith(
                          color: BusFlowColors.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('$err', style: BusFlowTypography.caption),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialDashboard extends StatelessWidget {
  final double totalContractedRevenue;
  final double protectedRevenue;
  final double revenueAtRisk;
  final double lostRevenue;
  final double riskPercentage;
  final double lossPercentage;

  const _FinancialDashboard({
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentage,
    required this.lossPercentage,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 800 ? 2 : 1;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 2.2,
          children: [
            _KpiCard(
              title: 'Receita Total Contratada',
              value: _currencyFormat.format(totalContractedRevenue),
              color: BusFlowColors.info,
              icon: Icons.account_balance_outlined,
            ),
            _KpiCard(
              title: 'Receita Protegida',
              value: _currencyFormat.format(protectedRevenue),
              color: BusFlowColors.success,
              icon: Icons.shield_outlined,
            ),
            _KpiCard(
              title: 'Receita em Risco',
              value: _currencyFormat.format(revenueAtRisk),
              color: BusFlowColors.warning,
              icon: Icons.warning_amber_outlined,
              percentage: riskPercentage,
            ),
            _KpiCard(
              title: 'Receita Perdida',
              value: _currencyFormat.format(lostRevenue),
              color: BusFlowColors.error,
              icon: Icons.trending_down_outlined,
              percentage: lossPercentage,
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
  final double? percentage;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header row: icon + title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: BusFlowTypography.kpiLabel.copyWith(
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Value row: amount + optional percentage badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: BusFlowTypography.kpiValue.copyWith(
                    color: color,
                    fontSize: 30,
                  ),
                ),
              ),
              if (percentage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${percentage!.toStringAsFixed(1)}%',
                    style: BusFlowTypography.badge.copyWith(
                      color: color,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
