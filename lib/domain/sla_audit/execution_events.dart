import 'domain_event.dart';
import 'verdict_evidence.dart';

/// Emitted when a vehicle is successfully bound to a contractual obligation.
class ExecutionBoundEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final String vehicleId;
  final DateTime bindingTimestampUtc;
  final double bindingLatitude; // Physical Metric - Double Required
  final double bindingLongitude; // Physical Metric - Double Required

  const ExecutionBoundEvent({
    required super.organizationId,
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
    required super.organizationId,
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
    required super.organizationId,
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
    required super.organizationId,
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
    required super.organizationId,
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
    required super.organizationId,
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
    required super.organizationId,
    required super.occurredAtUtc,
    required super.tripId,
    super.vehicleId,
    required super.operatorId,
    this.reason,
  });
}

// ── Sanction Lifecycle Events (Human-in-the-Loop, INV-23) ──────────────────

/// Emitted by the engine when a no-show penalty is assessed and queued for
/// human review. The engine NEVER emits [SanctionAppliedEvent] directly.
///
/// Satisfies INV-23: carries the full [VerdictEvidence] explaining the verdict.
class SanctionRecommendedEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final VerdictEvidence verdictEvidence;

  const SanctionRecommendedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.verdictEvidence,
  });
}

/// Emitted when an auditor/admin seals a recommended sanction.
///
/// Pillar C: [actorEmail] provides forensic traceability of the human actor.
class SanctionAppliedEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final String queueEntryId;
  final String approvedByUserId;
  final String actorEmail;
  final VerdictEvidence verdictEvidence;

  const SanctionAppliedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.queueEntryId,
    required this.approvedByUserId,
    required this.actorEmail,
    required this.verdictEvidence,
  });
}

/// Emitted when an auditor/admin refuses a recommended sanction.
///
/// Pillar C: [actorEmail] provides forensic traceability of the human actor.
class SanctionRejectedEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final String queueEntryId;
  final String rejectedByUserId;
  final String actorEmail;
  final String rejectionReason;
  final VerdictEvidence verdictEvidence;

  const SanctionRejectedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.queueEntryId,
    required this.rejectedByUserId,
    required this.actorEmail,
    required this.rejectionReason,
    required this.verdictEvidence,
  });
}

/// Emitted when a contractor disputes a recommended sanction.
class SanctionDisputedEvent extends DomainEvent {
  final String setId;
  final String contractId;
  final int planVersion;
  final String queueEntryId;
  final VerdictEvidence verdictEvidence;

  const SanctionDisputedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.queueEntryId,
    required this.verdictEvidence,
  });
}

// ── Justification Events (Phase 9.8.J) ──────────────────────────────────────

/// Emitted when a contractor/driver submits a justification for a SLA factEvent.
class JustificationSubmittedEvent extends DomainEvent {
  final String justificationId;
  final String setId;
  final String contractId;
  final int planVersion;
  final String actorUserId;
  final List<String> evidenceHashes;

  const JustificationSubmittedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.justificationId,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.actorUserId,
    required this.evidenceHashes,
  });
}

/// Emitted when an admin/operator approves a justification.
/// Triggers INHIBITED state on the linked execution (INV-15).
class JustificationApprovedEvent extends DomainEvent {
  final String justificationId;
  final String setId;
  final String contractId;
  final int planVersion;
  final String actorUserId;
  final String actorEmail;

  const JustificationApprovedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.justificationId,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.actorUserId,
    required this.actorEmail,
  });
}

/// Emitted when an admin/operator rejects a justification.
class JustificationRejectedEvent extends DomainEvent {
  final String justificationId;
  final String setId;
  final String contractId;
  final int planVersion;
  final String actorUserId;
  final String actorEmail;

  const JustificationRejectedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.justificationId,
    required this.setId,
    required this.contractId,
    required this.planVersion,
    required this.actorUserId,
    required this.actorEmail,
  });
}

// ── SLA Justification Events (CX-05 — Vehicle-Event Level) ──────────────────

/// Emitted when a driver submits a justification for a vehicle infraction occurrence.
///
/// Forensic anchor: [vehicleId] + [eventTimestamp] link back to the original
/// `VehicleOperationalState.stateChangedAt` from the Normalizer (CX-04).
class SLAJustificationSubmittedEvent extends DomainEvent {
  final String justificationId;
  final String vehicleId;
  final DateTime eventTimestamp;
  final String actorUserId;
  final List<String> evidenceHashes;

  const SLAJustificationSubmittedEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.justificationId,
    required this.vehicleId,
    required this.eventTimestamp,
    required this.actorUserId,
    required this.evidenceHashes,
  });
}

/// Emitted when a pending SLA justification is auto-expired (CX05-INV-22).
class SLAJustificationExpiredEvent extends DomainEvent {
  final String justificationId;
  final String vehicleId;
  final DateTime eventTimestamp;

  const SLAJustificationExpiredEvent({
    required super.organizationId,
    required super.occurredAtUtc,
    required this.justificationId,
    required this.vehicleId,
    required this.eventTimestamp,
  });
}
