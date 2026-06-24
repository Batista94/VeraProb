import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/sla_audit/projections/contract_financial_amendment_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');
final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// Append-only timeline of a contract's financial renegotiations
/// (`contract_financial_amendments`). Each node documents an effective change
/// to the penalty multiplier and/or financial ceiling — the forensic trail for
/// why a fine was computed under a given set of terms (INV-3, INV-23).
class ContractAmendmentsTimeline extends ConsumerWidget {
  final String contractId;

  const ContractAmendmentsTimeline({super.key, required this.contractId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amendmentsAsync = ref.watch(
      contractFinancialAmendmentsProvider(contractId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_outlined,
              size: 16,
              color: VeraProbColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Histórico de Aditivos Financeiros',
              style: VeraProbTypography.sectionTitle.copyWith(fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        switch (amendmentsAsync) {
          AsyncLoading() => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          AsyncError() => const _AmendmentsMessage(
            'Não foi possível carregar o histórico de aditivos.',
          ),
          AsyncData(:final value) =>
            value.isEmpty
                ? const _AmendmentsMessage(
                    'Nenhum aditivo financeiro registrado.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < value.length; i++)
                        _AmendmentNode(
                          amendment: value[i],
                          isFirst: i == 0,
                          isLast: i == value.length - 1,
                        ),
                    ],
                  ),
        },
      ],
    );
  }
}

class _AmendmentsMessage extends StatelessWidget {
  final String text;
  const _AmendmentsMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        text,
        style: const TextStyle(color: VeraProbColors.textSecondary),
      ),
    );
  }
}

/// One timeline entry: a rail (dot + connectors) on the left, an amendment card
/// on the right. The newest amendment is marked "VIGENTE".
class _AmendmentNode extends StatelessWidget {
  final ContractFinancialAmendmentView amendment;
  final bool isFirst;
  final bool isLast;

  const _AmendmentNode({
    required this.amendment,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final ceiling = amendment.financialCeilingCents;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline rail ──────────────────────────────────────────────
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : VeraProbColors.border,
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isFirst
                        ? VeraProbColors.primary
                        : VeraProbColors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isFirst
                          ? VeraProbColors.primary
                          : VeraProbColors.border,
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : VeraProbColors.border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Amendment card ─────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: VeraProbColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isFirst
                        ? VeraProbColors.primary.withValues(alpha: 0.4)
                        : VeraProbColors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Vigente desde '
                            '${_dateFormat.format(amendment.effectiveAtUtc.toLocal())}',
                            overflow: TextOverflow.ellipsis,
                            style: VeraProbTypography.dataValue.copyWith(
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (isFirst) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: VeraProbColors.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'VIGENTE',
                              style: VeraProbTypography.badge.copyWith(
                                color: VeraProbColors.primary,
                                fontSize: 8,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          label: 'Multiplicador de Multa',
                          value: amendment.penaltyMultiplierLabel,
                          color: VeraProbColors.error,
                        ),
                        _MetricChip(
                          label: 'Teto Financeiro',
                          value: ceiling == null
                              ? 'Sem teto'
                              : _currencyFormat.format(ceiling / 100.0),
                          color: ceiling == null
                              ? VeraProbColors.textSecondary
                              : VeraProbColors.onTime,
                        ),
                      ],
                    ),
                    if (amendment.notes != null &&
                        amendment.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        amendment.notes!.trim(),
                        style: VeraProbTypography.bodySmall.copyWith(
                          color: VeraProbColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Registrado em '
                      '${_dateTimeFormat.format(amendment.amendedAtUtc.toLocal())}',
                      style: VeraProbTypography.caption.copyWith(
                        color: VeraProbColors.textDisabled,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: VeraProbTypography.badge.copyWith(
            color: VeraProbColors.textDisabled,
            fontSize: 8,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: VeraProbTypography.dataValue.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
