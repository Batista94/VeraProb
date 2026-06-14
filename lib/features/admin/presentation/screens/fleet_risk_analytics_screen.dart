import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/analytics/fleet_risk_window.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/analytics/carrier_rank_table.dart';
import 'package:veraprob/features/admin/presentation/widgets/risk_thermometer_widget.dart';
import 'package:veraprob/state/providers/analytics_providers.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// Fleet Risk analytics dashboard — the host for [CarrierRankTable] and the
/// fleet risk sentinel ([RiskThermometerWidget] driven by the highest-risk
/// active window). Org-wide (INV-1: providers source org from
/// `currentOrganizationIdProvider`). URL: `/admin/hub/fleet-risk`.
class FleetRiskAnalyticsScreen extends ConsumerWidget {
  const FleetRiskAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Voltar',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.adminHub),
                icon: const Icon(
                  Icons.arrow_back,
                  color: VeraProbColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.insights_outlined,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Análise de Risco da Frota',
                  style: VeraProbTypography.sectionTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: const [
                _FleetRiskSentinelCard(),
                SizedBox(height: 20),
                CarrierRankTable(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The single highest-risk active SLA window, rendered through the existing
/// [RiskThermometerWidget]. Hidden-state safe: shows a calm message when no
/// active windows exist (Lesson 5: never a raw error/empty void).
class _FleetRiskSentinelCard extends ConsumerWidget {
  const _FleetRiskSentinelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(fleetRiskSummaryProvider);
    final sentinel = ref.watch(fleetRiskSentinelProvider);

    return Container(
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VeraProbColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_outlined,
                size: 18,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Sentinela de Risco — Janela Mais Crítica',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          switch (summaryAsync) {
            AsyncLoading() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            AsyncError() => const Text(
              'Não foi possível carregar o risco da frota.',
              style: TextStyle(color: VeraProbColors.textSecondary),
            ),
            AsyncData() =>
              sentinel == null
                  ? const Text(
                      'Nenhuma janela de SLA ativa no momento.',
                      style: TextStyle(color: VeraProbColors.textSecondary),
                    )
                  : _SentinelBody(sentinel: sentinel),
          },
        ],
      ),
    );
  }
}

class _SentinelBody extends StatelessWidget {
  final FleetRiskWindow sentinel;
  const _SentinelBody({required this.sentinel});

  @override
  Widget build(BuildContext context) {
    final nowUtc = DateTime.now().toUtc();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RiskThermometerWidget(
          report: sentinel.asBreachReport(nowUtc: nowUtc),
          height: 72,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Contrato',
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.textDisabled,
                  fontSize: 10,
                ),
              ),
              Tooltip(
                message: sentinel.contractId,
                child: Text(
                  sentinel.contractId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VeraProbTypography.dataValue.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Valor contratual em exposição',
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.textDisabled,
                  fontSize: 10,
                ),
              ),
              Text(
                _currencyFormat.format(sentinel.contractualValue.cents / 100.0),
                style: VeraProbTypography.dataValue.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: VeraProbColors.warning,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
