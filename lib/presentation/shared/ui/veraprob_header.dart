import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Standard header for veraprob screens.
///
/// Ensures mathematical alignment between icon, title, and actions.
/// Follows the 8px grid system defined in [VeraProbSpacing].
///
/// [leading] renders to the left of the icon (e.g. a back-button).
/// Nullable → existing callers are unaffected.
class VeraProbHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Color? iconColor;
  // Renders before the icon (e.g. an IconButton back-button).
  // Nullable so all existing call-sites remain unaffected.
  final Widget? leading;

  const VeraProbHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions,
    this.iconColor,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: VeraProbSpacing.xs),
        ],
        Icon(icon, size: 28, color: iconColor ?? VeraProbColors.primary),
        const SizedBox(width: VeraProbSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: VeraProbTypography.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (actions != null) ...[
          const SizedBox(width: VeraProbSpacing.md),
          ...actions!,
        ],
      ],
    );
  }
}
