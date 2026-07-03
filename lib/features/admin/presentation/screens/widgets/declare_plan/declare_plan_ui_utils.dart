import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/sla_audit/sla_template_presets.dart';
import 'package:veraprob/presentation/shared/ui/info_tooltip.dart';
import 'package:veraprob/features/admin/presentation/widgets/transport_vertical_chip.dart';

const kBrTimezones = [
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Belem',
  'America/Fortaleza',
  'America/Recife',
  'America/Noronha',
  'America/Cuiaba',
  'America/Porto_Velho',
  'America/Rio_Branco',
  'America/Boa_Vista',
];

int parseReaisToCents(String value) {
  if (value.trim().isEmpty) return 0;
  final clean = value.replaceAll('.', '').replaceAll(',', '.');
  final doubleVal = double.tryParse(clean) ?? 0.0;
  return (doubleVal * 100).round();
}

double parseDouble(String value) {
  if (value.trim().isEmpty) return 0.0;
  final clean = value.replaceAll(',', '.');
  return double.tryParse(clean) ?? 0.0;
}

String formatTime(TimeOfDay time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String formatCents(int cents) => NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$ ',
).format(cents / 100.0);

String formatDays(Set<int> days) {
  const map = {
    1: 'Seg',
    2: 'Ter',
    3: 'Qua',
    4: 'Qui',
    5: 'Sex',
    6: 'Sáb',
    7: 'Dom',
  };
  final sorted = days.toList()..sort();
  return sorted.map((d) => map[d] ?? '?').join(', ');
}

class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const SectionHeader({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: VeraProbColors.info),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: VeraProbColors.info,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class TemplateTile extends StatelessWidget {
  final SlaTemplateView template;
  final VoidCallback onTap;

  const TemplateTile({super.key, required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: template.vertical != null
          ? TransportVerticalChip(vertical: template.vertical!)
          : null,
      title: Text(template.name),
      subtitle: Text(
        _penaltySummary(template.penalties),
        style: VeraProbTypography.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SlaTemplatePresets.isPreset(template.id)
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: VeraProbColors.secondary.withValues(alpha: 0.15),
                borderRadius: VeraProbRadii.mdAll,
              ),
              child: Text(
                'SISTEMA',
                style: VeraProbTypography.badge.copyWith(
                  color: VeraProbColors.secondary,
                  fontSize: 9,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }

  String _penaltySummary(PenaltiesFormData p) {
    final delay = (p.delayPenaltyPerMinuteCents / 100.0).toStringAsFixed(2);
    final multiplier = (p.noShowPenaltyBps / 10000.0).toStringAsFixed(1);
    return '${multiplier}x no-show · '
        '${p.delayToleranceMinutes}min tol · '
        'R\$ $delay/min atraso';
  }
}

class ReviewRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const ReviewRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = VeraProbBreakpoints.isCompact(context);
    final Widget valueText = Text(
      value,
      style: const TextStyle(
        fontSize: 12,
        color: VeraProbColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
    );

    final List<Widget> content = [
      SizedBox(
        width: isNarrow ? null : 130,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: VeraProbColors.textSecondary,
          ),
        ),
      ),
      if (isNarrow) const SizedBox(height: 2),
      isNarrow ? valueText : Expanded(child: valueText),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: VeraProbColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  ),
          ),
        ],
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? period;
  final String? tooltip;

  const KpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.period,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: VeraProbColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: VeraProbColors.textSecondary,
                ),
              ),
              if (tooltip != null) ...[
                const SizedBox(width: 4),
                InfoTooltip(message: tooltip!, iconSize: 12),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: VeraProbColors.textPrimary,
                ),
              ),
              if (period != null) ...[
                const SizedBox(width: 4),
                Text(
                  period!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
