import 'package:flutter/material.dart';
import 'package:veraprob/application/super_admin/audit_event_category.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Compact badge that visually classifies an audit event by category.
///
/// Renders a chip-like widget with a category-specific color, icon, and
/// label derived from [AuditEventCategory]. Used inside each audit log
/// item in [TenantAuditTab] to provide at-a-glance categorisation.
///
/// **Category → Visual mapping (deterministic, Req 7.4):**
/// - [AuditEventCategory.infrastructure] → Indigo + settings icon
/// - [AuditEventCategory.governance] → Teal + gavel icon
/// - [AuditEventCategory.security] → Amber + shield icon
/// - [AuditEventCategory.operational] → Blue + build icon
///
/// **INV-11:** `const` constructor for optimal rebuild performance.
/// **INV-22:** Resides in `lib/features/super_admin/presentation/widgets/`.
class AuditCategoryBadge extends StatelessWidget {
  /// The audit event category to display.
  final AuditEventCategory category;

  /// Creates an [AuditCategoryBadge] for the given [category].
  const AuditCategoryBadge({super.key, required this.category});

  /// Returns the accent color for the given [category].
  Color _colorForCategory(AuditEventCategory category) {
    return switch (category) {
      AuditEventCategory.infrastructure => VeraProbColors.secondary,
      AuditEventCategory.governance => VeraProbColors.primary,
      AuditEventCategory.security => VeraProbColors.warning,
      AuditEventCategory.operational => VeraProbColors.info,
    };
  }

  /// Returns the leading icon for the given [category].
  IconData _iconForCategory(AuditEventCategory category) {
    return switch (category) {
      AuditEventCategory.infrastructure => Icons.settings_outlined,
      AuditEventCategory.governance => Icons.gavel_outlined,
      AuditEventCategory.security => Icons.shield_outlined,
      AuditEventCategory.operational => Icons.build_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForCategory(category);

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
          Icon(_iconForCategory(category), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            category.label,
            style: VeraProbTypography.badge.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
