import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Relative "time ago" label for alert timestamps (UTC input, INV-6).
String formatAlertTimeAgo(DateTime utcTime) {
  final diff = DateTime.now().toUtc().difference(utcTime);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  return 'há ${diff.inDays}d';
}

/// Caption with tabular figures so stacked timestamps align vertically.
TextStyle alertTimestampStyle() => VeraProbTypography.caption.copyWith(
  fontFeatures: [const FontFeature.tabularFigures()],
);

/// Compact outlined action button used in alert card footers.
class AlertActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;
  final String? error;

  const AlertActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.color,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = error != null
        ? VeraProbColors.critical
        : (color ?? VeraProbColors.textSecondary);

    return SizedBox(
      height: 28,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: btnColor,
          side: BorderSide(color: btnColor.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: VeraProbRadii.mdAll,
          ),
          textStyle: VeraProbTypography.badge,
        ),
        child: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 12),
                    const SizedBox(width: 4),
                  ],
                  Text(error ?? label),
                ],
              ),
      ),
    );
  }
}

/// Outlined severity/type badge (e.g. "NO-SHOW", "CONTESTAÇÃO").
class AlertSeverityBadge extends StatelessWidget {
  final String label;
  final Color color;

  const AlertSeverityBadge({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: VeraProbRadii.smAll,
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Photo burst counter badge ("+N FOTOS" / "10 FOTOS").
class AlertPhotoCountBadge extends StatelessWidget {
  final int count;

  const AlertPhotoCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    // "10 FOTOS" for exact 10, "+N FOTOS" for burst < 10
    final label = count >= 10 ? '$count FOTOS' : '+$count FOTOS';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: VeraProbColors.primary.withValues(alpha: 0.12),
        borderRadius: VeraProbRadii.smAll,
        border: Border.all(
          color: VeraProbColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: VeraProbColors.primary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
