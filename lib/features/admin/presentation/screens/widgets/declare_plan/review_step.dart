import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

import 'declare_plan_ui_utils.dart';
import 'shift_draft_snapshot.dart';

/// Step 4 of the Declare Contract Plan wizard — Risk Exposure & Review.
///
/// Shows financial KPI summary (protected revenue, no-show exposure, relative
/// risk against the contract ceiling) followed by per-turn detail cards and an
/// immutability disclaimer. Requires Riverpod to read [contractDetailProvider].
class ReviewStep extends ConsumerWidget {
  const ReviewStep({
    super.key,
    required this.allTurns,
    required this.contractId,
  });

  final List<ShiftDraftSnapshot> allTurns;
  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compute hash string for display (uses all patterns)
    String hashDisplay = '—';
    if (allTurns.isNotEmpty) {
      final draftHash = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'contract_id': contractId,
                'patterns': allTurns
                    .map(
                      (d) => {
                        'origin': d.originZoneId,
                        'destination': d.destinationZoneId,
                        'arrival': formatTime(d.arrivalTime),
                        'departure': formatTime(d.departureTime),
                        'tz': d.timezone,
                        'category': d.requiredVehicleCategory.toJson(),
                      },
                    )
                    .toList(),
              }),
            ),
          )
          .toString();
      hashDisplay = draftHash;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumo de exposição financeira e revisão detalhada dos turnos antes da publicação.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
        const SizedBox(height: 16),

        _RiskSummary(allTurns: allTurns, contractId: contractId),

        const SizedBox(height: 16),

        // ── Turn cards ────────────────────────────────────────
        ...allTurns.asMap().entries.map((entry) {
          final i = entry.key;
          final d = entry.value;
          final label = allTurns.length == 1
              ? 'Turno Único'
              : i == 0
              ? 'Turno ${i + 1} — Ida'
              : 'Turno ${i + 1} — Retorno';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: VeraProbColors.info.withValues(alpha: 0.10),
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: VeraProbRadii.mdAll,
                side: BorderSide(color: VeraProbColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_bus,
                          size: 16,
                          color: VeraProbColors.info,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: VeraProbColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ReviewRow(
                      icon: Icons.route,
                      label: 'Rota',
                      value: '${d.originZoneName}  →  ${d.destinationZoneName}',
                    ),
                    ReviewRow(
                      icon: Icons.calendar_today,
                      label: 'Dias',
                      value: formatDays(d.selectedDays),
                    ),
                    ReviewRow(
                      icon: Icons.schedule,
                      label: 'Horários',
                      value:
                          'Partida ${formatTime(d.departureTime)}  ·  Chegada ${formatTime(d.arrivalTime)}  ·  ${d.timezone}',
                    ),
                    ReviewRow(
                      icon: Icons.directions_bus_outlined,
                      label: 'Categoria exigida',
                      value: d.requiredVehicleCategory.label,
                    ),
                    const Divider(height: 20, color: VeraProbColors.border),
                    ReviewRow(
                      icon: Icons.attach_money,
                      label: 'Valor base',
                      value: formatCents(d.baseValueCents),
                    ),
                    ReviewRow(
                      icon: Icons.timer,
                      label: 'Pontualidade',
                      value:
                          'Carência: ${d.gracePeriodMinutes} min  ·  Atraso: ${d.delayToleranceMinutes} min  ·  Antecipação: ${d.earlyArrivalToleranceMinutes} min  ·  Permanência mín: ${d.dwellTimeMinutes} min',
                    ),
                    ReviewRow(
                      icon: Icons.warning_amber_rounded,
                      label: 'No-Show',
                      value:
                          '${(d.noShowPenaltyBps / 10000).toStringAsFixed(1)}x valor base  ·  Teto: ${d.noShowThresholdMinutes} min',
                    ),
                    ReviewRow(
                      icon: Icons.money_off,
                      label: 'Multas',
                      value:
                          '${formatCents(d.delayPenaltyCentsPerMinute)}/min atraso  ·  Downgrade: ${formatCents(d.downgradePenaltyCents)}',
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        const SizedBox(height: 8),

        // ── Hash ──────────────────────────────────────────────
        Tooltip(
          message: hashDisplay,
          child: Row(
            children: [
              const Icon(
                Icons.fingerprint,
                size: 14,
                color: VeraProbColors.textDisabled,
              ),
              const SizedBox(width: 6),
              Text(
                'SHA-256: ${hashDisplay.length > 16 ? '${hashDisplay.substring(0, 16)}…' : hashDisplay}',
                style: VeraProbTypography.mono(
                  size: 11,
                  color: VeraProbColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Imutabilidade ─────────────────────────────────────
        const Text(
          '⚠️ Após publicado, este Padrão de Turno não poderá ser modificado diretamente. Uma nova versão do plano precisará ser declarada.',
          style: TextStyle(
            color: VeraProbColors.warning,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _RiskSummary extends ConsumerWidget {
  const _RiskSummary({required this.allTurns, required this.contractId});

  final List<ShiftDraftSnapshot> allTurns;
  final String contractId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (allTurns.isEmpty) return const SizedBox.shrink();

    final contractDetailAsync = ref.watch(contractDetailProvider(contractId));
    final contract = contractDetailAsync.value?.summary;
    final financialCeilingCents = contract?.financialCeilingCents;

    int totalProtectedRevenueCents = 0;
    int totalMaxNoShowExposureCents = 0;
    int absoluteMaxPenaltyPerTripCents = 0;

    for (final d in allTurns) {
      // 4.33 weeks/month on avg; cyclic turns run only 1 week every 4.
      final multiplier = d.weekCycle == WeekCycle.everyWeek ? 4.33 : 1.083;
      final tripsPerMonth = d.selectedDays.length * multiplier;

      final revenue = (d.baseValueCents * tripsPerMonth).round();
      final noShowPenalty = Money(
        d.baseValueCents,
      ).multiplyByBps(d.noShowPenaltyBps).cents;
      final noShowExposure = (noShowPenalty * tripsPerMonth).round();
      final delayPenaltyCeiling =
          d.delayPenaltyCentsPerMinute * d.noShowThresholdMinutes;
      final maxTripPenalty = noShowPenalty > delayPenaltyCeiling
          ? noShowPenalty
          : delayPenaltyCeiling;

      totalProtectedRevenueCents += revenue;
      totalMaxNoShowExposureCents += noShowExposure;
      if (maxTripPenalty > absoluteMaxPenaltyPerTripCents) {
        absoluteMaxPenaltyPerTripCents = maxTripPenalty;
      }
    }

    double? relativeRisk;
    if (financialCeilingCents != null && financialCeilingCents > 0) {
      relativeRisk =
          (totalMaxNoShowExposureCents / financialCeilingCents) * 100;
    }

    final hasBaseTripValue = allTurns.any((d) => d.baseValueCents > 0);
    final cardWidth =
        (MediaQuery.sizeOf(context).width - 80) /
        (VeraProbBreakpoints.isCompact(context) ? 1 : 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasBaseTripValue)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: VeraProbColors.warning,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Configure o Valor Base por Viagem no Step 3 para habilitar os KPIs financeiros.',
                    style: TextStyle(
                      fontSize: 12,
                      color: VeraProbColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                icon: Icons.shield_outlined,
                label: 'Receita Protegida',
                value: formatCents(totalProtectedRevenueCents),
                period: '/mês',
                tooltip:
                    'Soma dos valores contratuais por viagem × volume mensal projetado.',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                icon: Icons.warning_amber_rounded,
                label: 'Exposição No-Show',
                value: formatCents(totalMaxNoShowExposureCents),
                period: '/mês',
                tooltip:
                    'Risco máximo em caso de 100% de falha No-Show em todos os turnos.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: KpiCard(
                icon: Icons.money_off,
                label: 'Penalidade Máx.',
                value: formatCents(absoluteMaxPenaltyPerTripCents),
                period: '/viagem',
                tooltip:
                    'Maior penalidade possível em um único evento (No-Show ou Atraso Crítico).',
              ),
            ),
            if (relativeRisk != null)
              SizedBox(
                width: cardWidth,
                child: KpiCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Risco Relativo',
                  value: '${relativeRisk.toStringAsFixed(1)}%',
                  period: 'do teto',
                  tooltip:
                      'Percentual do Teto Financeiro ocupado pela exposição máxima de No-Show mensal.',
                ),
              )
            else
              SizedBox(
                width: cardWidth,
                child: const KpiCard(
                  icon: Icons.lock_outline,
                  label: 'Risco Relativo',
                  value: '—',
                  tooltip:
                      'Configure o Teto Financeiro no contrato para habilitar este indicador.',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 32, color: VeraProbColors.border),
      ],
    );
  }
}
