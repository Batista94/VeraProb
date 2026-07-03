import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';

import 'package:veraprob/application/shared/app_types.dart';

/// Compact status chip for [JustificationStatus].
///
/// pending → amber · approved → green · rejected → red.
/// Portuguese labels used throughout (OCC language standard).
class JustificationStatusBadge extends StatelessWidget {
  final JustificationStatus status;

  const JustificationStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    switch (status) {
      case JustificationStatus.pending:
        color = VeraProbColors.warning;
        label = 'PENDENTE';
      case JustificationStatus.approved:
        color = VeraProbColors.success;
        label = 'APROVADA';
      case JustificationStatus.rejected:
        color = VeraProbColors.error;
        label = 'REJEITADA';
      case JustificationStatus.expired:
        color = VeraProbColors.textSecondary;
        label = 'EXPIRADA';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: VeraProbRadii.lgAll,
      ),
      child: Text(
        label,
        style: VeraProbTypography.badge.copyWith(color: color),
      ),
    );
  }
}
