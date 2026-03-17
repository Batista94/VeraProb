import 'package:equatable/equatable.dart';

/// A transit route, normalized from GTFS or manually created.
class TransitRoute extends Equatable {
  final String id;
  final String organizationId;
  final String? gtfsRouteId;
  final String shortName;
  final String longName;
  final String? color; // Hex color from GTFS
  final String? agencyId;
  final DateTime? createdAt;

  // Denormalized: live operational stats
  final int? activeTripsCount;

  const TransitRoute({
    required this.id,
    required this.organizationId,
    this.gtfsRouteId,
    required this.shortName,
    required this.longName,
    this.color,
    this.agencyId,
    this.createdAt,
    this.activeTripsCount,
  });

  /// Route display combining short and long names
  String get displayName => '$shortName — $longName';

  TransitRoute copyWith({
    String? id,
    String? organizationId,
    String? gtfsRouteId,
    String? shortName,
    String? longName,
    String? color,
    String? agencyId,
    DateTime? createdAt,
    int? activeTripsCount,
  }) {
    return TransitRoute(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      gtfsRouteId: gtfsRouteId ?? this.gtfsRouteId,
      shortName: shortName ?? this.shortName,
      longName: longName ?? this.longName,
      color: color ?? this.color,
      agencyId: agencyId ?? this.agencyId,
      createdAt: createdAt ?? this.createdAt,
      activeTripsCount: activeTripsCount ?? this.activeTripsCount,
    );
  }

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      gtfsRouteId: json['gtfs_route_id'] as String?,
      shortName: json['short_name'] as String? ?? json['name'] as String? ?? '',
      longName: json['long_name'] as String? ?? '',
      color: json['color'] as String?,
      agencyId: json['agency_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'organization_id': organizationId,
      'gtfs_route_id': gtfsRouteId,
      'short_name': shortName,
      'long_name': longName,
      'color': color,
      'agency_id': agencyId,
    };
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    gtfsRouteId,
    shortName,
    longName,
    color,
    agencyId,
  ];
}
