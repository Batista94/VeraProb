import 'domain_event.dart';

/// Emitted when a vehicle is successfully bound to a contractual obligation.
class ExecutionBoundEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final String vehicleId;
  final DateTime bindingTimestampUtc;
  final double bindingLatitude;
  final double bindingLongitude;

  const ExecutionBoundEvent({
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.vehicleId,
    required this.bindingTimestampUtc,
    required this.bindingLatitude,
    required this.bindingLongitude,
  });
}

/// Emitted when a contractual obligation is declared as a no-show
/// (time window expired with no matching vehicle).
class NoShowDeclaredEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final DateTime declaredAtUtc;

  const NoShowDeclaredEvent({
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.declaredAtUtc,
  });
}

/// Emitted when a contractual obligation is declared as an evidence gap
/// (insufficient telemetry to determine execution).
class EvidenceGapDeclaredEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final DateTime declaredAtUtc;

  const EvidenceGapDeclaredEvent({
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.declaredAtUtc,
  });
}

// ── Evidence Events (Human Interventions) ───────────────────

/// Base class for human-originated operational facts that bypass the standard
/// contractual evaluation state machine. These serve exclusively as
/// unalterable forensic anchors in the Ledger.
abstract class EvidenceEvent extends DomainEvent {
  final String tripId; // Maps to setId in the SLA domain
  final String? vehicleId;
  final String operatorId;

  const EvidenceEvent({
    required super.occurredAtUtc,
    required this.tripId,
    this.vehicleId,
    required this.operatorId,
  });
}

/// Emitted when an operator manually registers an occurrence via OCC.
class OccurrenceRegisteredEvidence extends EvidenceEvent {
  final String occurrenceType;
  final String? notes;
  final Map<String, dynamic> metadata;

  const OccurrenceRegisteredEvidence({
    required super.occurredAtUtc,
    required super.tripId,
    super.vehicleId,
    required super.operatorId,
    required this.occurrenceType,
    this.notes,
    this.metadata = const {},
  });
}

/// Emitted when an operator manually interrupts a trip via OCC.
class TripInterruptedEvidence extends EvidenceEvent {
  final String? reason;

  const TripInterruptedEvidence({
    required super.occurredAtUtc,
    required super.tripId,
    super.vehicleId,
    required super.operatorId,
    this.reason,
  });
}

/// Emitted when an operator manually cancels a trip via OCC.
class TripCancelledEvidence extends EvidenceEvent {
  final String? reason;

  const TripCancelledEvidence({
    required super.occurredAtUtc,
    required super.tripId,
    super.vehicleId,
    required super.operatorId,
    this.reason,
  });
}
