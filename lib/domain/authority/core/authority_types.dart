import 'package:equatable/equatable.dart';

/// Value Object representing the distinct operational action intended by a Command.
///
/// We do NOT use enums to allow future extensibility by modules/plugins without
/// modifying the core system, preventing architectural lockdown.
class OperationalActionType extends Equatable {
  final String key;

  const OperationalActionType(this.key);

  // Example predefined actions (not exhaustive)
  static const resolveAlert = OperationalActionType('resolve_alert');
  static const acknowledgeAlert = OperationalActionType('acknowledge_alert');
  static const overrideTripStatus = OperationalActionType(
    'manual_status_override',
  );
  static const reassignVehicle = OperationalActionType('reassign_vehicle');
  static const overrideRouteDeviation = OperationalActionType(
    'override_route_deviation',
  );
  static const assignDriver = OperationalActionType('assign_driver');
  static const createTripEvent = OperationalActionType('create_trip_event');

  @override
  List<Object?> get props => [key];

  @override
  String toString() => 'ActionType($key)';
}

/// Value Object identifying the human or system Actor.
class ActorId extends Equatable {
  final String value;

  const ActorId(this.value);

  @override
  List<Object?> get props => [value];
}

/// Value Object identifying the organizational Role.
///
/// Kept as a VO (not Enum) to support organizational hierarchies (multi-tenant)
/// that differ between clients.
class RoleId extends Equatable {
  final String value;

  const RoleId(this.value);

  @override
  List<Object?> get props => [value];
}

/// Value Object defining the semantic target of an Action.
/// E.g. "trip:uuid", "vehicle:abc-1234"
class TargetRef extends Equatable {
  final String entityType;
  final String entityId;

  const TargetRef(this.entityType, this.entityId);

  String get urn => 'urn:PactaFlow:$entityType:$entityId';

  @override
  List<Object?> get props => [entityType, entityId];
}
