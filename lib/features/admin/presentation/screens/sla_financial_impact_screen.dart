import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';

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
      color: VeraProbColors.background,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Impacto Financeiro do SLA',
              style: VeraProbTypography.sectionTitle.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Visão executiva de proteção de margem contratual',
              style: VeraProbTypography.bodySmall.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: impactAsync.when(
                data: (impact) => _FinancialDashboard(
                  totalContractedRevenue: impact.totalContractedRevenue / 100.0,
                  protectedRevenue: impact.protectedRevenue / 100.0,
                  revenueAtRisk: impact.revenueAtRisk / 100.0,
                  lostRevenue: impact.lostRevenue / 100.0,
                  riskPercentageBps: impact.riskPercentageBps,
                  lossPercentageBps: impact.lossPercentageBps,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: VeraProbColors.error,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Erro ao carregar impacto financeiro',
                        style: VeraProbTypography.bodyMedium.copyWith(
                          color: VeraProbColors.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('$err', style: VeraProbTypography.caption),
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
  final int riskPercentageBps;
  final int lossPercentageBps;

  const _FinancialDashboard({
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentageBps,
    required this.lossPercentageBps,
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
              color: VeraProbColors.info,
              icon: Icons.account_balance_outlined,
            ),
            _KpiCard(
              title: 'Receita Protegida',
              value: _currencyFormat.format(protectedRevenue),
              color: VeraProbColors.success,
              icon: Icons.shield_outlined,
            ),
            _KpiCard(
              title: 'Receita em Risco',
              value: _currencyFormat.format(revenueAtRisk),
              color: VeraProbColors.warning,
              icon: Icons.warning_amber_outlined,
              percentageBps: riskPercentageBps,
            ),
            _KpiCard(
              title: 'Receita Perdida',
              value: _currencyFormat.format(lostRevenue),
              color: VeraProbColors.error,
              icon: Icons.trending_down_outlined,
              percentageBps: lossPercentageBps,
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
  final int? percentageBps;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.percentageBps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
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
                  style: VeraProbTypography.kpiLabel.copyWith(
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
                  style: VeraProbTypography.kpiValue.copyWith(
                    color: color,
                    fontSize: 30,
                  ),
                ),
              ),
              if (percentageBps != null)
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
                    '${(percentageBps! / 100).toStringAsFixed(1)}%',
                    style: VeraProbTypography.badge.copyWith(
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
