import 'package:equatable/equatable.dart';

/// A transit stop (bus stop), normalized from GTFS.
class Stop extends Equatable {
  final String id;
  final String? gtfsStopId;
  final String name;
  final double latitude;
  final double longitude;

  const Stop({
    required this.id,
    this.gtfsStopId,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      id: json['id'] as String,
      gtfsStopId: json['gtfs_stop_id'] as String?,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gtfs_stop_id': gtfsStopId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  @override
  List<Object?> get props => [id, gtfsStopId, name, latitude, longitude];
}
