import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Semantic variant for [InfoTooltip] that drives default icon and color.
enum InfoTooltipVariant { help, warning, info, error, success }

/// A standardized contextual help icon with tooltip.
///
/// Wraps [Tooltip] + [Icon] with consistent sizing, semantic color,
/// and WCAG 2.2 screen-reader support.
///
/// Usage in a form `suffixIcon`:
/// ```dart
/// suffixIcon: const InfoTooltip(message: 'Explanation text'),
/// ```
///
/// Usage for a warning state with custom icon:
/// ```dart
/// const InfoTooltip(
///   message: 'Sem geofence — o motor não pode auditar automaticamente.',
///   variant: InfoTooltipVariant.warning,
///   icon: Icons.location_off,
/// )
/// ```
class InfoTooltip extends StatelessWidget {
  const InfoTooltip({
    super.key,
    required this.message,
    this.variant = InfoTooltipVariant.help,
    this.icon,
    this.iconColor,
    this.iconSize = 16.0,
    this.semanticLabel,
  });

  final String message;
  final InfoTooltipVariant variant;

  /// Overrides the variant's default icon.
  final IconData? icon;

  /// Overrides the variant's default color.
  final Color? iconColor;

  final double iconSize;

  /// Overrides the Semantics label (defaults to [message]).
  final String? semanticLabel;

  IconData _resolveIcon() {
    if (icon != null) return icon!;
    return switch (variant) {
      InfoTooltipVariant.help => Icons.help_outline,
      InfoTooltipVariant.warning => Icons.warning_amber_rounded,
      InfoTooltipVariant.info => Icons.info_outline,
      InfoTooltipVariant.error => Icons.error_outline,
      InfoTooltipVariant.success => Icons.check_circle_outline,
    };
  }

  Color _resolveColor(BuildContext context) {
    if (iconColor != null) return iconColor!;
    return switch (variant) {
      InfoTooltipVariant.help => Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.45),
      InfoTooltipVariant.warning => VeraProbColors.warning,
      InfoTooltipVariant.info => VeraProbColors.info,
      InfoTooltipVariant.error => VeraProbColors.error,
      InfoTooltipVariant.success => VeraProbColors.success,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? message,
      child: Tooltip(
        message: message,
        child: Icon(
          _resolveIcon(),
          size: iconSize,
          color: _resolveColor(context),
          semanticLabel: '',
        ),
      ),
    );
  }
}
