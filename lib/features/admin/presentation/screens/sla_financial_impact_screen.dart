import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_series.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/presentation/shared/ui/kpi_sparkline_card.dart';
import 'package:veraprob/presentation/shared/ui/skeleton_list_loader.dart';
import 'package:veraprob/presentation/shared/ui/veraprob_header.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// Visão Executiva — CFO-grade SLA financial protection dashboard.
///
/// Renamed from "Impacto Financeiro" per Council rename directive.
///
/// INV-4: all monetary values received as cents (int) and converted to
/// double ONLY at the display boundary via [_formatCents].
class SlaFinancialImpactScreen extends ConsumerWidget {
  const SlaFinancialImpactScreen({super.key});

  /// Bridge Conversion — Double Required: cents → decimal for NumberFormat.
  static String _formatCents(int cents) => _currencyFormat.format(
    cents / 100.0,
  ); // Bridge Conversion — Double Required

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(sparklineWindowProvider);
    final impactAsync = ref.watch(financialImpactProvider);
    final sparklineAsync = ref.watch(financialSparklineProvider(window));

    return ColoredBox(
      color: VeraProbColors.background,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VeraProbHeader(
              icon: Icons.account_balance_outlined,
              title: 'Visão Executiva',
              subtitle: 'Proteção de margem contratual SLA',
            ),
            const SizedBox(height: VeraProbSpacing.md),
            _WindowSegmentedButton(
              selected: window,
              onChanged: (days) =>
                  ref.read(sparklineWindowProvider.notifier).set(days),
            ),
            const SizedBox(height: VeraProbSpacing.lg),
            Expanded(
              child: _buildContent(context, impactAsync, sparklineAsync),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncValue<ContractualFinancialImpact> impactAsync,
    AsyncValue<FinancialSparklineSeries> sparklineAsync,
  ) {
    // Error state (no stale data available)
    if (impactAsync.hasError && !impactAsync.hasValue) {
      return _buildError();
    }

    // Loading: show skeleton only on first load (no previous data)
    if (impactAsync is AsyncLoading && !impactAsync.hasValue) {
      return const SkeletonListLoader(itemCount: 4);
    }

    final impact = impactAsync.value;
    if (impact == null) return _buildError();

    // Sparkline may still be loading — show empty series gracefully
    final sparkline = sparklineAsync.value ?? FinancialSparklineSeries.empty;

    return _FinancialDashboard(
      impact: impact,
      sparkline: sparkline,
      formatCents: _formatCents,
      onCardTap: (_) => context.go(AdminNav.slaAudit.path),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: VeraProbColors.error,
            size: 48,
          ),
          const SizedBox(height: VeraProbSpacing.md),
          Text(
            'Falha ao carregar visão executiva',
            style: VeraProbTypography.bodyMedium.copyWith(
              color: VeraProbColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Window toggle ──────────────────────────────────────────

class _WindowSegmentedButton extends StatelessWidget {
  final int selected;
  final void Function(int days) onChanged;

  const _WindowSegmentedButton({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 7, label: Text('7 dias')),
        ButtonSegment(value: 30, label: Text('30 dias')),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
      style: SegmentedButton.styleFrom(
        backgroundColor: VeraProbColors.surface,
        foregroundColor: VeraProbColors.textSecondary,
        selectedBackgroundColor: VeraProbColors.primary.withValues(alpha: 0.15),
        selectedForegroundColor: VeraProbColors.primary,
        side: const BorderSide(color: VeraProbColors.border),
      ),
    );
  }
}

// ── KPI Grid ──────────────────────────────────────────────

class _FinancialDashboard extends StatelessWidget {
  final ContractualFinancialImpact impact;
  final FinancialSparklineSeries sparkline;
  final String Function(int cents) formatCents;
  final void Function(String category) onCardTap;

  const _FinancialDashboard({
    required this.impact,
    required this.sparkline,
    required this.formatCents,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            constraints.maxWidth >= VeraProbBreakpoints.compact ? 2 : 1;
        // Fixed-height cards: avoids fragile childAspectRatio.
        const cardHeight = 160.0;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: VeraProbSpacing.md,
          mainAxisSpacing: VeraProbSpacing.md,
          mainAxisExtent: cardHeight,
          children: [
            KpiSparklineCard(
              title: 'Receita Total Contratada',
              value: formatCents(impact.totalContractedRevenue),
              color: VeraProbColors.info,
              icon: Icons.account_balance_outlined,
              sparklineSeries: sparkline.protectedCents,
              onTap: () => onCardTap('total'),
            ),
            KpiSparklineCard(
              title: 'Receita Protegida',
              value: formatCents(impact.protectedRevenue),
              color: VeraProbColors.success,
              icon: Icons.shield_outlined,
              sparklineSeries: sparkline.protectedCents,
              onTap: () => onCardTap('protegida'),
            ),
            KpiSparklineCard(
              title: 'Receita em Risco',
              value: formatCents(impact.revenueAtRisk),
              color: VeraProbColors.warning,
              icon: Icons.warning_amber_outlined,
              sparklineSeries: sparkline.atRiskCents,
              percentageBps: impact.riskPercentageBps,
              onTap: () => onCardTap('risco'),
            ),
            KpiSparklineCard(
              title: 'Receita Perdida',
              value: formatCents(impact.lostRevenue),
              color: VeraProbColors.error,
              icon: Icons.trending_down_outlined,
              sparklineSeries: sparkline.lostCents,
              percentageBps: impact.lossPercentageBps,
              onTap: () => onCardTap('perdida'),
            ),
          ],
        );
      },
    );
  }
}
