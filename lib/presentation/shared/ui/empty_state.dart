import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Shared empty state widget for VeraProb screens.
///
/// Use this instead of private `_EmptyState` widgets scattered across screens.
/// Provides consistent icon, title, description, and optional action button.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Optional call-to-action widget (e.g. [FilledButton] or [OutlinedButton]).
  final Widget? action;

  /// Icon color. Defaults to [VeraProbColors.textDisabled].
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VeraProbSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: iconColor ?? VeraProbColors.textDisabled,
            ),
            const SizedBox(height: VeraProbSpacing.md),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: VeraProbColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: VeraProbColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: VeraProbSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
