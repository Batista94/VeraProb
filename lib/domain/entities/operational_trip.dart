import 'package:equatable/equatable.dart';
import '../enums/trip_status.dart';
import 'operational_warning.dart';

/// The central domain entity of BusFlow.
///
/// An OperationalTrip represents a single execution of a scheduled trip.
/// It binds a driver, a vehicle, and a route together for a specific
/// time window, and tracks the real-time operational state.
class OperationalTrip extends Equatable {
  final String id;
  final String? scheduledTripId;
  final String? driverId;
  final String? vehicleId;
  final String routeId;
  final TripStatus status;
  final DateTime scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final int delaySeconds;
  final double completionPct;
  final String sourceType; // 'manual', 'gtfs_static', 'gtfs_realtime'
  final String? externalTripId;

  // Intelligence / Engine Fields
  final int severityScore; // 0-100 indicating operational risk
  final List<OperationalWarning> warnings;

  // Denormalized display fields (populated from joins)
  final String? driverName;
  final String? vehiclePlate;
  final String? routeShortName;
  final String? routeLongName;
  final String? routeColor;

  const OperationalTrip({
    required this.id,
    this.scheduledTripId,
    this.driverId,
    this.vehicleId,
    required this.routeId,
    this.status = TripStatus.scheduled,
    required this.scheduledStart,
    this.scheduledEnd,
    this.actualStart,
    this.actualEnd,
    this.delaySeconds = 0,
    this.completionPct = 0.0,
    this.sourceType = 'manual',
    this.externalTripId,
    this.severityScore = 0,
    this.warnings = const [],
    this.driverName,
    this.vehiclePlate,
    this.routeShortName,
    this.routeLongName,
    this.routeColor,
  });

  /// Whether this trip is currently active (in-progress)
  bool get isActive => status.isActive;

  /// Whether this trip needs operator attention
  bool get requiresAttention => status.requiresAttention || severityScore > 29;

  /// Whether this trip is finished
  bool get isTerminal => status.isTerminal;

  /// Whether the trip has a driver and vehicle assigned
  bool get isFullyAssigned => driverId != null && vehicleId != null;

  /// Human-readable delay string
  String get delayDisplay {
    if (delaySeconds == 0) return 'No horário';
    final minutes = delaySeconds ~/ 60;
    if (minutes < 1) return '< 1 min';
    return '+$minutes min';
  }

  /// Display name combining route short name and long name
  String get routeDisplay {
    if (routeShortName != null && routeLongName != null) {
      return '$routeShortName — $routeLongName';
    }
    return routeShortName ?? routeLongName ?? routeId;
  }

  OperationalTrip copyWith({
    String? id,
    String? scheduledTripId,
    String? driverId,
    String? vehicleId,
    String? routeId,
    TripStatus? status,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    DateTime? actualStart,
    DateTime? actualEnd,
    int? delaySeconds,
    double? completionPct,
    String? sourceType,
    String? externalTripId,
    int? severityScore,
    List<OperationalWarning>? warnings,
    String? driverName,
    String? vehiclePlate,
    String? routeShortName,
    String? routeLongName,
    String? routeColor,
  }) {
    return OperationalTrip(
      id: id ?? this.id,
      scheduledTripId: scheduledTripId ?? this.scheduledTripId,
      driverId: driverId ?? this.driverId,
      vehicleId: vehicleId ?? this.vehicleId,
      routeId: routeId ?? this.routeId,
      status: status ?? this.status,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      actualStart: actualStart ?? this.actualStart,
      actualEnd: actualEnd ?? this.actualEnd,
      delaySeconds: delaySeconds ?? this.delaySeconds,
      completionPct: completionPct ?? this.completionPct,
      sourceType: sourceType ?? this.sourceType,
      externalTripId: externalTripId ?? this.externalTripId,
      severityScore: severityScore ?? this.severityScore,
      warnings: warnings ?? this.warnings,
      driverName: driverName ?? this.driverName,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      routeShortName: routeShortName ?? this.routeShortName,
      routeLongName: routeLongName ?? this.routeLongName,
      routeColor: routeColor ?? this.routeColor,
    );
  }

  factory OperationalTrip.fromJson(Map<String, dynamic> json) {
    return OperationalTrip(
      id: json['id'] as String,
      scheduledTripId: json['scheduled_trip_id'] as String?,
      driverId: json['driver_id'] as String?,
      vehicleId: json['vehicle_id'] as String?,
      routeId: json['route_id'] as String,
      status: TripStatus.fromString(json['status'] as String? ?? 'scheduled'),
      scheduledStart: DateTime.parse(json['scheduled_start'] as String),
      scheduledEnd: json['scheduled_end'] != null
          ? DateTime.parse(json['scheduled_end'] as String)
          : null,
      actualStart: json['actual_start'] != null
          ? DateTime.parse(json['actual_start'] as String)
          : null,
      actualEnd: json['actual_end'] != null
          ? DateTime.parse(json['actual_end'] as String)
          : null,
      delaySeconds: json['delay_seconds'] as int? ?? 0,
      completionPct: (json['completion_pct'] as num?)?.toDouble() ?? 0.0,
      sourceType: json['source_type'] as String? ?? 'manual',
      externalTripId: json['external_trip_id'] as String?,
      severityScore: json['severity_score'] as int? ?? 0,
      warnings: [], // Warnings are ephemeral, not persisted directly yet
      // Denormalized fields from joins
      driverName:
          json['driver_name'] as String? ??
          (json['drivers'] as Map<String, dynamic>?)?['full_name'] as String?,
      vehiclePlate:
          json['vehicle_plate'] as String? ??
          (json['vehicles'] as Map<String, dynamic>?)?['plate'] as String?,
      routeShortName:
          json['route_short_name'] as String? ??
          (json['routes'] as Map<String, dynamic>?)?['short_name'] as String?,
      routeLongName:
          json['route_long_name'] as String? ??
          (json['routes'] as Map<String, dynamic>?)?['long_name'] as String?,
      routeColor:
          (json['routes'] as Map<String, dynamic>?)?['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scheduled_trip_id': scheduledTripId,
      'driver_id': driverId,
      'vehicle_id': vehicleId,
      'route_id': routeId,
      'status': status.dbValue,
      'scheduled_start': scheduledStart.toIso8601String(),
      'scheduled_end': scheduledEnd?.toIso8601String(),
      'actual_start': actualStart?.toIso8601String(),
      'actual_end': actualEnd?.toIso8601String(),
      'delay_seconds': delaySeconds,
      'completion_pct': completionPct,
      'source_type': sourceType,
      'external_trip_id': externalTripId,
      'severity_score': severityScore,
    };
  }

  @override
  List<Object?> get props => [
    id,
    scheduledTripId,
    driverId,
    vehicleId,
    routeId,
    status,
    scheduledStart,
    scheduledEnd,
    actualStart,
    actualEnd,
    delaySeconds,
    completionPct,
    sourceType,
    externalTripId,
    severityScore,
    warnings,
  ];
}
