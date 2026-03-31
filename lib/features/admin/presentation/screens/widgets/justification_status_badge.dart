import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../domain/sla_audit/justification/justification_status.dart';

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
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: VeraProbTypography.badge.copyWith(color: color),
      ),
    );
  }
}
