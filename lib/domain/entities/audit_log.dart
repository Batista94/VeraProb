// pr_scanner: ignore-regression
//
import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Represents an immutable record of a manual intervention or automated critical
/// action within the veraprob operational environment.
///
/// Used for legal accountability, operational review, and debugging.
class AuditLog extends Equatable {
  final String id;
  final String organizationId;
  final String operatorId;
  final String actionType;
  final String entityId;
  final String? oldValue;
  final String? newValue;
  final String? reason;
  final DateTime timestamp;
  final ActorType? actorType;
  final String? impersonatorId;

  AuditLog({
    required this.id,
    required this.organizationId,
    required this.operatorId,
    required this.actionType,
    required this.entityId,
    this.oldValue,
    this.newValue,
    this.reason,
    required this.timestamp,
    this.actorType,
    this.impersonatorId,
  }) {
    // INV-10: If actor is impersonator, impersonatorId is mandatory.
    if (actorType == ActorType.impersonator && impersonatorId == null) {
      throw const IntegrityException(
        'impersonatorId is required when actorType is IMPERSONATOR',
        field: 'impersonatorId',
      );
    }
  }

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
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      actorType: json['actor_type'] != null
          ? ActorType.fromString(json['actor_type'] as String)
          : null,
      impersonatorId: json['impersonator_id'] as String?,
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
      if (actorType != null) 'actor_type': actorType!.dbValue,
      if (impersonatorId != null) 'impersonator_id': impersonatorId,
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
    actorType,
    impersonatorId,
  ];
}
