import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/super_admin/quota_warning_view_model.dart';

/// Health card for a tenant organization.
///
/// Displays connection status, ROI, telemetry volume, and quota warnings.
///
/// **INV-4 / Lens 2:** The [warning] parameter uses [QuotaWarningViewModel]
/// (application layer) instead of [QuotaWarning] (domain).
class OrgHealthCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final QuotaWarningViewModel? warning;

  const OrgHealthCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: VeraProbColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: VeraProbColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (warning != null) _QuotaWarningBadge(warning: warning!),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: valueColor ?? VeraProbColors.textPrimary,
              ),
            ),
            if (warning != null) ...[
              const SizedBox(height: 4),
              Text(
                '${warning!.currentCount}/${warning!.maxAllowed} (${warning!.usagePct}%)',
                style: TextStyle(
                  fontSize: 11,
                  color: warning!.isCritical
                      ? VeraProbColors.error
                      : VeraProbColors.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuotaWarningBadge extends StatelessWidget {
  final QuotaWarningViewModel warning;

  const _QuotaWarningBadge({required this.warning});

  @override
  Widget build(BuildContext context) {
    final color = warning.isCritical
        ? VeraProbColors.error
        : warning.isUrgent
        ? Colors.orange
        : VeraProbColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            warning.isCritical
                ? Icons.error_outline
                : Icons.warning_amber_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${warning.threshold}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
