import 'package:equatable/equatable.dart';

/// Represents an immutable record of a manual intervention or automated critical
/// action within the veraprob operational environment.
///
/// Used for legal accountability, operational review, and debugging.
class AuditLog extends Equatable {
  final String id;

  /// The Tenant / Organization ID that owns this audit record. Isolated boundary.
  final String organizationId;

  /// ID of the user (Admin, Supervisor, Operator) taking the action
  final String operatorId;

  /// A generalized string explaining what happened (e.g., "TRIP_STATUS_CHANGE", "DEVICE_OFFLINE")
  final String actionType;

  /// The UUID of the entity being acted upon (Trip ID, Driver ID, Vehicle ID)
  final String entityId;

  /// Stringified previous state (e.g., "TripStatus.enRoute")
  final String? oldValue;

  /// Stringified new state (e.g., "TripStatus.detour")
  final String? newValue;

  /// Human readable reason or system-generated notes
  final String? reason;

  /// Strict server-side or localized timestamp of the event
  final DateTime timestamp;

  const AuditLog({
    required this.id,
    required this.organizationId,
    required this.operatorId,
    required this.actionType,
    required this.entityId,
    this.oldValue,
    this.newValue,
    this.reason,
    required this.timestamp,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String,
      operatorId: json['operator_id'] as String,
      actionType: json['action_type'] as String,
      entityId: json['entity_id'] as String,
      oldValue: json['old_value'] as String?,
      newValue: json['new_value'] as String?,
      reason: json['reason'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'operator_id': operatorId,
      'action_type': actionType,
      'entity_id': entityId,
      'old_value': oldValue,
      'new_value': newValue,
      'reason': reason,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    operatorId,
    actionType,
    entityId,
    oldValue,
    newValue,
    reason,
    timestamp,
  ];
}
