import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/state/providers/analytics_providers.dart';

/// Carrier Performance Ranking — worst-compliance contracts first.
///
/// Reads [carrierRankingProvider] (server-ranked via `mv_carrier_performance`).
/// Industrial Dark; narrow-safe (Lesson 3: contract id flexes + ellipsis +
/// Tooltip). Compliance is colored semantically (Emerald/Amber/Red).
class CarrierRankTable extends ConsumerWidget {
  const CarrierRankTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(carrierRankingProvider);

    return Container(
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.lgAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.leaderboard_outlined,
                size: 18,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Ranking de Performance — Transportadoras',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ranking.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Não foi possível carregar o ranking.',
                style: TextStyle(color: VeraProbColors.textSecondary),
              ),
            ),
            data: (rows) => rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Sem contratos avaliados ainda.',
                      style: TextStyle(color: VeraProbColors.textSecondary),
                    ),
                  )
                : Column(
                    children: [
                      const _RankHeaderRow(),
                      const Divider(height: 16, color: VeraProbColors.border),
                      for (final r in rows) _RankDataRow(rank: r),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RankHeaderRow extends StatelessWidget {
  const _RankHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: VeraProbColors.textSecondary,
      letterSpacing: 0.4,
    );
    return const Row(
      children: [
        Expanded(flex: 4, child: Text('CONTRATO', style: style)),
        Expanded(
          flex: 2,
          child: Text('CONFORM.', style: style, textAlign: TextAlign.right),
        ),
        Expanded(
          flex: 2,
          child: Text('DISPUTAS', style: style, textAlign: TextAlign.right),
        ),
        Expanded(
          flex: 3,
          child: Text('EXPOSIÇÃO', style: style, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class _RankDataRow extends StatelessWidget {
  final CarrierPerformanceRank rank;

  const _RankDataRow({required this.rank});

  Color get _complianceColor {
    if (rank.complianceRateBps >= 9500) return VeraProbColors.success;
    if (rank.complianceRateBps >= 8000) return VeraProbColors.warning;
    return VeraProbColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final compliance = (rank.complianceRateBps / 100).toStringAsFixed(2);
    final exposure = rank.fineExposure.toDouble().toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Tooltip(
              message: rank.contractId,
              child: Text(
                rank.contractId,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$compliance%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _complianceColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${rank.disputeCount}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'R\$ $exposure',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
