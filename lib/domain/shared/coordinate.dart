import 'dart:math' as math;
import 'package:equatable/equatable.dart';

class Coordinate extends Equatable {
  final double latitude;
  final double longitude;

  const Coordinate(this.latitude, this.longitude)
    : assert(latitude >= -90 && latitude <= 90),
      assert(longitude >= -180 && longitude <= 180);

  int distanceTo(Coordinate other) {
    const double earthRadius = 6371000;
    final double dLat = _degToRad(other.latitude - latitude);
    final double dLon = _degToRad(other.longitude - longitude);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(latitude)) *
            math.cos(_degToRad(other.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return (earthRadius * c).round();
  }

  double _degToRad(double deg) => deg * (math.pi / 180);

  @override
  List<Object?> get props => [latitude, longitude];
}
