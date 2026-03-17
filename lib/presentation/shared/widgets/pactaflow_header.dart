import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Standard header for PactaFlow screens.
/// 
/// Ensures mathematical alignment between icon, title, and actions.
/// Follows the 8px grid system defined in [PactaFlowSpacing].
class PactaFlowHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Color? iconColor;

  const PactaFlowHeader({
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
        Icon(
          icon,
          size: 28,
          color: iconColor ?? PactaFlowColors.primary,
        ),
        const SizedBox(width: PactaFlowSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: PactaFlowTypography.sectionTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: PactaFlowTypography.bodySmall.copyWith(
                    color: PactaFlowColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (actions != null) ...[
          const SizedBox(width: PactaFlowSpacing.md),
          ...actions!,
        ],
      ],
    );
  }
}
