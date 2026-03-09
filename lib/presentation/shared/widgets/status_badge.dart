import 'package:flutter/material.dart';
import '../../../domain/enums/trip_status.dart';
import '../trip_status_theme.dart';

/// A compact badge showing trip status with color and label.
class StatusBadge extends StatelessWidget {
  final TripStatus status;
  final bool compact;

  const StatusBadge({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: compact ? 12 : 14, color: status.color),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              status.label,
              style: TextStyle(
                color: status.color,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
