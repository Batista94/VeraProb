import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Placeholder for the Trips Timeline screen.
/// Will display a Gantt-style timeline of all trips for the day.
class TripsTimelineScreen extends StatelessWidget {
  const TripsTimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: VeraProbColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timeline_outlined,
              size: 64,
              color: VeraProbColors.secondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'TIMELINE DE VIAGENS',
              style: TextStyle(
                color: VeraProbColors.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Visualização temporal Gantt de todas as viagens do dia',
              style: TextStyle(
                color: VeraProbColors.textDisabled,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
