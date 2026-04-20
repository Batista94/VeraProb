import 'package:equatable/equatable.dart';

import 'justification_status.dart';

/// Immutable audit trail entry for SLA justification status transitions.
///
/// Every status change (PENDING → APPROVED, PENDING → REJECTED,
/// PENDING → EXPIRED) generates exactly one log entry with full
/// actor attribution and temporal precision (INV-6: UTC mandatory).
///
/// [callerRole] seals the authority level under which the decision was made.
/// The Red Team auditor can verify that only authorized roles produced
/// APPROVED/REJECTED transitions.
///
/// These records are append-only — no update or delete (INV-3).
class JustificationAuditLog extends Equatable {
  final String id;
  final String justificationId;
  final String userId;

  /// The role under which the actor executed this transition.
  /// Sealed for forensic responsibility attribution.
  /// 'SYSTEM' for automated transitions (e.g., expiration).
  final String callerRole;

  final JustificationStatus previousStatus;
  final JustificationStatus newStatus;

  /// UTC timestamp of the transition (INV-6).
  final DateTime timestamp;

  const JustificationAuditLog({
    required this.id,
    required this.justificationId,
    required this.userId,
    required this.callerRole,
    required this.previousStatus,
    required this.newStatus,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [
    id,
    justificationId,
    userId,
    callerRole,
    previousStatus,
    newStatus,
    timestamp,
  ];
}
