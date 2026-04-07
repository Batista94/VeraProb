import 'dart:collection';
import 'package:veraprob/domain/entities/vehicle_position.dart';

/// Stateless weighted-average smoother for GPS position and speed.
///
/// All methods are pure functions — no internal state is owned here.
/// Weights are calibrated to reduce jitter while preserving reactivity:
/// oldest sample = 15 %, middle = 25 %, most recent = 60 %.
class SpatialSmoother {
  static const List<double> _weights = [
    // Physical Metric - Double Required
    0.15,
    0.25,
    0.60,
  ];

  const SpatialSmoother();

  /// Returns (latitude, longitude) as a weighted average of [buffer].
  ///
  /// Falls back to the single position when buffer has only 1 entry.
  (double, double) applySmoothing(
    Queue<VehiclePosition> buffer,
  ) {
    // Physical Metric - Double Required
    if (buffer.length == 1) {
      return (buffer.first.latitude, buffer.first.longitude);
    }

    final positions = buffer.toList();
    final weights = _weights.sublist(_weights.length - positions.length);
    final weightSum = weights.reduce((a, b) => a + b);

    double lat = 0; // Physical Metric - Double Required
    double lng = 0; // Physical Metric - Double Required
    for (int i = 0; i < positions.length; i++) {
      final w = weights[i] / weightSum;
      lat += positions[i].latitude * w;
      lng += positions[i].longitude * w;
    }
    return (lat, lng);
  }

  /// Returns smoothed speed in km/h as a weighted average of [buffer].
  double smoothSpeed(Queue<VehiclePosition> buffer) {
    // Physical Metric - Double Required
    final positions = buffer.toList();
    final weights = _weights.sublist(_weights.length - positions.length);
    final weightSum = weights.reduce((a, b) => a + b);

    double speed = 0; // Physical Metric - Double Required
    for (int i = 0; i < positions.length; i++) {
      final w = weights[i] / weightSum;
      speed += (positions[i].speed ?? 0.0) * w;
    }
    return speed;
  }
}
