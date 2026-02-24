import 'package:flutter/material.dart';
import '../../../../domain/enums/trip_status.dart';

/// A map marker representing a vehicle, colored by trip status.
///
/// Renders as a directional arrow (when heading is known) or a dot,
/// with the trip's status color and a route label.
class VehicleMarkerWidget extends StatelessWidget {
  final TripStatus status;
  final String routeLabel;
  final double? heading;
  final bool isSelected;
  final bool isStale;
  final VoidCallback? onTap;

  const VehicleMarkerWidget({
    super.key,
    required this.status,
    required this.routeLabel,
    this.heading,
    this.isSelected = false,
    this.isStale = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    final opacity = isStale ? 0.4 : 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Route label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                routeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Vehicle dot
            Container(
              width: isSelected ? 18 : 14,
              height: isSelected ? 18 : 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white70,
                  width: isSelected ? 3 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: isSelected ? 8 : 4,
                    spreadRadius: isSelected ? 2 : 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: status == TripStatus.atStop
                  ? Icon(
                      Icons.hail,
                      size: isSelected ? 10 : 8,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
