import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';

/// A vehicle (bus) in the fleet.
class Vehicle extends Equatable {
  final String id;

  /// Optimistic locking version counter. Auto-incremented on each UPDATE.
  /// Used to detect concurrent modifications (Lost Update prevention).
  final int version;

  final String organizationId;
  final String plate;
  final String? model;
  final int capacity;
  final VehicleStatus status;
  final DateTime? createdAt;

  // Denormalized: current assignment (if any)
  final String? currentTripId;
  final String? currentRouteShortName;

  const Vehicle({
    required this.id,
    this.version = 1,
    required this.organizationId,
    required this.plate,
    this.model,
    required this.capacity,
    this.status = VehicleStatus.available,
    this.createdAt,
    this.currentTripId,
    this.currentRouteShortName,
  });

  bool get isAvailable => status == VehicleStatus.available;
  bool get isInService => status == VehicleStatus.inService;

  String get displayName => '$plate${model != null ? ' ($model)' : ''}';

  Vehicle copyWith({
    String? id,
    int? version,
    String? organizationId,
    String? plate,
    String? model,
    int? capacity,
    VehicleStatus? status,
    DateTime? createdAt,
    String? currentTripId,
    String? currentRouteShortName,
  }) {
    return Vehicle(
      id: id ?? this.id,
      version: version ?? this.version,
      organizationId: organizationId ?? this.organizationId,
      plate: plate ?? this.plate,
      model: model ?? this.model,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      currentTripId: currentTripId ?? this.currentTripId,
      currentRouteShortName:
          currentRouteShortName ?? this.currentRouteShortName,
    );
  }

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      organizationId: json['organization_id'] as String,
      plate: json['plate'] as String,
      model: json['model'] as String?,
      capacity: json['capacity'] as int,
      status: VehicleStatus.fromString(
        json['status'] as String? ?? 'available',
      ),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'organization_id': organizationId,
      'plate': plate,
      'model': model,
      'capacity': capacity,
      'status': status.dbValue,
    };
  }

  @override
  List<Object?> get props => [
    id,
    version,
    organizationId,
    plate,
    model,
    capacity,
    status,
  ];
}
