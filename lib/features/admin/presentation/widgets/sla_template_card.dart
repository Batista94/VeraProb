import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/sla_audit/sla_template.dart';
import '../../../../application/sla_audit/sla_template_presets.dart';
import 'transport_vertical_chip.dart';

/// Card widget for displaying an SLA template in the gallery.
///
/// Shows name, vertical badge, and a compact penalty summary.
/// System presets display a "Sistema" badge and only offer a "Clone" action.
/// Org-owned templates offer Edit, Clone, and Delete actions.
class SlaTemplateCard extends StatelessWidget {
  final SlaTemplate template;
  final VoidCallback? onClone;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const SlaTemplateCard({
    super.key,
    required this.template,
    this.onClone,
    this.onEdit,
    this.onDelete,
  });

  bool get _isPreset => SlaTemplatePresets.isPreset(template.id);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.name,
                    style: VeraProbTypography.dataValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isPreset)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: VeraProbColors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'SISTEMA',
                      style: VeraProbTypography.badge.copyWith(
                        color: VeraProbColors.secondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (template.vertical != null)
              TransportVerticalChip(vertical: template.vertical!),
            if (template.description != null &&
                template.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                template.description!,
                style: VeraProbTypography.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            _PenaltySummary(template: template),
            const Spacer(),
            const Divider(color: VeraProbColors.border),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isPreset && onEdit != null)
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Editar',
                    onPressed: onEdit!,
                  ),
                if (onClone != null)
                  _ActionButton(
                    icon: Icons.copy_outlined,
                    label: 'Clonar',
                    onPressed: onClone!,
                  ),
                if (!_isPreset && onDelete != null)
                  _ActionButton(
                    icon: Icons.delete_outline,
                    label: 'Excluir',
                    onPressed: onDelete!,
                    color: VeraProbColors.error,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PenaltySummary extends StatelessWidget {
  final SlaTemplate template;
  const _PenaltySummary({required this.template});

  @override
  Widget build(BuildContext context) {
    final p = template.penalties;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        _MiniStat(label: 'No-Show', value: '${p.noShowPenaltyMultiplier}x'),
        _MiniStat(label: 'Tolerância', value: '${p.delayToleranceMinutes} min'),
        _MiniStat(
          label: 'Atraso/min',
          value: _formatCents(p.delayPenaltyPerMinute.cents),
        ),
        _MiniStat(
          label: 'Downgrade',
          value: _formatCents(p.downgradePenaltyFlat.cents),
        ),
      ],
    );
  }

  String _formatCents(int cents) {
    final reais = cents ~/ 100;
    final centavos = cents % 100;
    return 'R\$ $reais${centavos > 0 ? ',${centavos.toString().padLeft(2, '0')}' : ''}';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: VeraProbTypography.caption),
        Text(value, style: VeraProbTypography.kpiLabel),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color ?? VeraProbColors.textSecondary,
        textStyle: VeraProbTypography.caption,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
