import 'package:equatable/equatable.dart';

/// Domain entity representing an operational alert derived from
/// the contractual evaluation pipeline.
///
/// Alerts are persistent, tenant-scoped signals emitted when the
/// evaluation engine produces a decision requiring operator attention.
class OperationalAlert extends Equatable {
  final String id;
  final String organizationId;
  final String entityId;
  final String contractId;
  final String alertType;
  final String severity;
  final DateTime triggeredAtUtc;
  final String? triggeringEventId;
  final String? traceId;
  final Map<String, dynamic> context;
  final String status;
  final DateTime? acknowledgedAtUtc;
  final String? acknowledgedByUserId;
  final DateTime? resolvedAtUtc;

  /// User IDs that have viewed this alert (collision awareness).
  final List<String> viewedByUserIds;

  const OperationalAlert({
    required this.id,
    required this.organizationId,
    required this.entityId,
    required this.contractId,
    required this.alertType,
    required this.severity,
    required this.triggeredAtUtc,
    this.triggeringEventId,
    this.traceId,
    this.context = const {},
    this.status = 'ACTIVE',
    this.acknowledgedAtUtc,
    this.acknowledgedByUserId,
    this.resolvedAtUtc,
    this.viewedByUserIds = const [],
  });

  /// Creates an acknowledged copy of this alert.
  OperationalAlert acknowledge(String userId, DateTime atUtc) {
    return OperationalAlert(
      id: id,
      organizationId: organizationId,
      entityId: entityId,
      contractId: contractId,
      alertType: alertType,
      severity: severity,
      triggeredAtUtc: triggeredAtUtc,
      triggeringEventId: triggeringEventId,
      traceId: traceId,
      context: context,
      status: 'ACKNOWLEDGED',
      acknowledgedAtUtc: atUtc,
      acknowledgedByUserId: userId,
      resolvedAtUtc: resolvedAtUtc,
      viewedByUserIds: viewedByUserIds,
    );
  }

  /// Creates a resolved copy of this alert.
  OperationalAlert resolve(DateTime atUtc) {
    return OperationalAlert(
      id: id,
      organizationId: organizationId,
      entityId: entityId,
      contractId: contractId,
      alertType: alertType,
      severity: severity,
      triggeredAtUtc: triggeredAtUtc,
      triggeringEventId: triggeringEventId,
      traceId: traceId,
      context: context,
      status: 'RESOLVED',
      acknowledgedAtUtc: acknowledgedAtUtc,
      acknowledgedByUserId: acknowledgedByUserId,
      resolvedAtUtc: atUtc,
      viewedByUserIds: viewedByUserIds,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    entityId,
    contractId,
    alertType,
    severity,
    triggeredAtUtc,
    triggeringEventId,
    traceId,
    context,
    status,
    acknowledgedAtUtc,
    acknowledgedByUserId,
    resolvedAtUtc,
    viewedByUserIds,
  ];
}
