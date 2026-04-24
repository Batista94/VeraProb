import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// Compact badge showing evidence compliance fraction (e.g. "2/3 ✅").
/// Used in [SanctionVerdictCard] for at-a-glance compliance status.
///
/// INV-7: No domain logic — pure display.
class ComplianceBadge extends StatelessWidget {
  final ComplianceCheckResult? compliance;

  const ComplianceBadge({super.key, required this.compliance});

  @override
  Widget build(BuildContext context) {
    final c = compliance;
    if (c == null) return const SizedBox.shrink();

    if (c is NoActiveTrip) return const SizedBox.shrink();

    if (c is NoRequirements) {
      return _Badge(
        label: '${(c).evidenceCount} evidências',
        color: VeraProbColors.success,
        icon: Icons.check_circle_outline,
      );
    }

    final active = c as ActiveCompliance;
    if (active.totalRequired == 0) return const SizedBox.shrink();

    final isComplete = active.isComplete;
    return _Badge(
      label: '${active.totalFulfilled}/${active.totalRequired}',
      color: isComplete ? VeraProbColors.success : VeraProbColors.warning,
      icon: isComplete
          ? Icons.check_circle_outline
          : Icons.warning_amber_outlined,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _Badge({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Expandable checklist of required evidence types with fulfillment status.
/// Used in [EvidenceDossierModal] above the photo grid.
///
/// INV-7: No domain logic — pure display.
class EvidenceComplianceChecklist extends StatefulWidget {
  final ActiveCompliance compliance;

  const EvidenceComplianceChecklist({super.key, required this.compliance});

  @override
  State<EvidenceComplianceChecklist> createState() =>
      _EvidenceComplianceChecklistState();
}

class _EvidenceComplianceChecklistState
    extends State<EvidenceComplianceChecklist> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final c = widget.compliance;
    if (c.totalRequired == 0) return const SizedBox.shrink();

    final progressFraction = c.totalRequired > 0
        ? c.totalFulfilled / c.totalRequired
        : 1.0;
    final progressColor = c.isComplete
        ? VeraProbColors.success
        : VeraProbColors.warning;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with progress bar and toggle
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.checklist_rounded, size: 14, color: progressColor),
                  const SizedBox(width: 6),
                  Text(
                    'Conformidade: ${c.totalFulfilled}/${c.totalRequired}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: progressColor,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: VeraProbColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progressFraction,
                minHeight: 3,
                backgroundColor: VeraProbColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
          ),
          // Checklist items (collapsible)
          if (_expanded) ...[
            const SizedBox(height: 8),
            for (final item in c.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                child: Row(
                  children: [
                    Icon(
                      item.isFulfilled
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: item.isFulfilled
                          ? VeraProbColors.success
                          : VeraProbColors.textDisabled,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: item.isFulfilled
                            ? VeraProbColors.textPrimary
                            : VeraProbColors.textSecondary,
                      ),
                    ),
                    if (item.count > 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${item.count})',
                        style: const TextStyle(
                          fontSize: 10,
                          color: VeraProbColors.textDisabled,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }
}
