import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_delta.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';
import 'package:veraprob/presentation/sandbox/widgets/dashboard/sandbox_delta_bps.dart';
import 'package:veraprob/presentation/sandbox/widgets/dashboard/sandbox_rule_breakdown.dart';
import 'package:veraprob/presentation/theme/sandbox_theme_extension.dart';

/// A/B Delta results dashboard for a completed SLA Sandbox session.
///
/// Consumes a hydrated [session] + per-event [results] (from Step-1 query
/// providers). Simulated money always uses the `~` prefix + [simulatedValueColor].
class SandboxResultsDashboard extends StatelessWidget {
  final SandboxSimulationSession session;
  final List<SandboxSimulationResult> results;
  final bool isLoading;
  final VoidCallback onExit;
  final VoidCallback? onExportPdf;

  const SandboxResultsDashboard({
    super.key,
    required this.session,
    required this.results,
    required this.isLoading,
    required this.onExit,
    this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<SandboxThemeExtension>() ??
        SandboxThemeExtension.defaults();
    final delta = SandboxSimulationDelta.fromSession(session);
    final bps =
        session.deltaBps ??
        SandboxDeltaBps.compute(
          baselineCents: session.baselineTotalFines.cents,
          simulatedCents: session.simulatedTotalFines.cents,
        );
    final rows = SandboxRuleBreakdownRow.fromResults(results);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ROI SIMULATOR — Sessão "${session.sessionLabel}"',
          style: VeraProbTypography.sectionTitle.copyWith(
            color: tokens.accentColor,
          ),
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        Text(
          'Contrato: ${session.contractId}  ·  '
          '${session.baselineEventCount} eventos',
          style: VeraProbTypography.caption,
        ),
        const SizedBox(height: VeraProbSpacing.lg),
        _AbCards(session: session, tokens: tokens),
        const SizedBox(height: VeraProbSpacing.lg),
        _DeltaImpact(delta: delta, bps: bps, tokens: tokens),
        const SizedBox(height: VeraProbSpacing.lg),
        _RuleBreakdownTable(rows: rows, tokens: tokens),
        const SizedBox(height: VeraProbSpacing.xl),
        Row(
          children: [
            FilledButton(
              onPressed: isLoading ? null : (onExportPdf ?? () {}),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.accentColor,
                foregroundColor: VeraProbColors.background,
              ),
              child: const Text('Exportar PDF'),
            ),
            const SizedBox(width: VeraProbSpacing.sm),
            TextButton(
              onPressed: onExit,
              style: TextButton.styleFrom(foregroundColor: tokens.accentColor),
              child: const Text('Sair do Modo Simulação'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AbCards extends StatelessWidget {
  final SandboxSimulationSession session;
  final SandboxThemeExtension tokens;

  const _AbCards({required this.session, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MoneyCard(
            title: 'BASELINE',
            subtitle: '(Regras Atuais)',
            amountLabel: SandboxCurrencyFormat.formatCents(
              session.baselineTotalFines.cents,
              prefix: '',
            ),
            amountColor: VeraProbColors.textPrimary,
            borderColor: VeraProbColors.border,
          ),
        ),
        const SizedBox(width: VeraProbSpacing.md),
        Icon(Icons.arrow_forward, color: tokens.accentColor),
        const SizedBox(width: VeraProbSpacing.md),
        Expanded(
          child: _MoneyCard(
            title: 'SIMULADO',
            subtitle: '(Regras Hipotéticas)',
            amountLabel: SandboxCurrencyFormat.formatCents(
              session.simulatedTotalFines.cents,
            ),
            amountColor: tokens.simulatedValueColor,
            borderColor: tokens.tableBorderColor,
          ),
        ),
      ],
    );
  }
}

class _MoneyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amountLabel;
  final Color amountColor;
  final Color borderColor;

  const _MoneyCard({
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.amountColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: VeraProbSpacing.cardPadding,
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: VeraProbTypography.badge),
          Text(subtitle, style: VeraProbTypography.caption),
          const SizedBox(height: VeraProbSpacing.sm),
          Text(
            amountLabel,
            style: VeraProbTypography.dataValue.copyWith(color: amountColor),
          ),
          Text('Total Multas', style: VeraProbTypography.caption),
        ],
      ),
    );
  }
}

class _DeltaImpact extends StatelessWidget {
  final SandboxSimulationDelta delta;
  final int? bps;
  final SandboxThemeExtension tokens;

  const _DeltaImpact({
    required this.delta,
    required this.bps,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final isSavings = delta.direction == SandboxDeltaDirection.savings;
    final isIncrease = delta.direction == SandboxDeltaDirection.increase;
    final accent = isSavings
        ? VeraProbColors.success
        : (isIncrease ? VeraProbColors.warning : VeraProbColors.neutral);
    final fill = accent.withValues(alpha: 0.12);
    final arrow = isSavings
        ? Icons.arrow_downward
        : (isIncrease ? Icons.arrow_upward : Icons.remove);
    final title = isSavings
        ? 'ECONOMIA PROJETADA'
        : (isIncrease ? 'AUMENTO PROJETADO' : 'SEM VARIAÇÃO');

    final ratio = delta.baselineTotalFines.cents <= 0
        ? 0.0
        : (delta.deltaCents.abs() / delta.baselineTotalFines.cents).clamp(
            0.0,
            1.0,
          );

    return KeyedSubtree(
      key: const Key('sandbox-delta-impact'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: VeraProbRadii.mdAll,
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: VeraProbSpacing.sectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: VeraProbTypography.badge.copyWith(color: accent),
              ),
              const SizedBox(height: VeraProbSpacing.sm),
              Row(
                children: [
                  Icon(arrow, color: accent, size: 20),
                  const SizedBox(width: VeraProbSpacing.xs),
                  Text(
                    SandboxCurrencyFormat.formatCents(delta.deltaAmount.cents),
                    style: tokens.simulatedValueStyle.copyWith(color: accent),
                  ),
                  if (bps != null) ...[
                    const SizedBox(width: VeraProbSpacing.sm),
                    Text(
                      '(${SandboxDeltaBps.format(bps!)} bps)',
                      style: VeraProbTypography.bodySmall.copyWith(
                        color: accent,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: VeraProbSpacing.sm),
              ClipRRect(
                borderRadius: VeraProbRadii.smAll,
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: VeraProbColors.surfaceElevated,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleBreakdownTable extends StatelessWidget {
  final List<SandboxRuleBreakdownRow> rows;
  final SandboxThemeExtension tokens;

  const _RuleBreakdownTable({required this.rows, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border(
          left: BorderSide(color: tokens.tableBorderColor, width: 3),
        ),
      ),
      padding: VeraProbSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DETALHAMENTO POR TIPO DE REGRA',
            style: VeraProbTypography.badge.copyWith(color: tokens.accentColor),
          ),
          const SizedBox(height: VeraProbSpacing.sm),
          if (rows.isEmpty)
            Text('Sem eventos no período.', style: VeraProbTypography.caption)
          else
            ...rows.map((row) => _RuleRow(row: row, tokens: tokens)),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final SandboxRuleBreakdownRow row;
  final SandboxThemeExtension tokens;

  const _RuleRow({required this.row, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final bps = row.deltaBps;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VeraProbSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(row.ruleType, style: VeraProbTypography.bodySmall),
          ),
          Expanded(
            flex: 2,
            child: Text(
              SandboxCurrencyFormat.formatCents(row.baselineCents, prefix: ''),
              style: VeraProbTypography.caption,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              SandboxCurrencyFormat.formatCents(row.simulatedCents),
              style: VeraProbTypography.caption.copyWith(
                color: tokens.simulatedValueColor,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            child: Text(
              bps == null ? '—' : '${SandboxDeltaBps.format(bps)} bps',
              style: VeraProbTypography.caption,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
