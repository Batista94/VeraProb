import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Standard header for veraprob screens.
///
/// Ensures mathematical alignment between icon, title, and actions.
/// Follows the 8px grid system defined in [VeraProbSpacing].
class VeraProbHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Color? iconColor;

  const VeraProbHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
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
