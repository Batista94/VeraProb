import 'package:veraprob/domain/sla_audit/contract_events.dart';
import 'package:veraprob/domain/sla_audit/contractual_plan_declared_event.dart';
import 'package:veraprob/domain/sla_audit/domain_event.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

export '../../domain/sla_audit/sla_ledger_entry.dart';

/// Application Service mapping DomainEvents to forensic SlaLedgerEntries.
///
/// This mapping decouples the internal domain event structure from the
/// external forensic record, fulfilling the requirement for application-level
/// forensic mapping and explicit causal linkage.
class SlaLedgerMapper {
  /// Maps a [DomainEvent] to its forensic [SlaLedgerEntry].
  static SlaLedgerEntry mapToEntry(DomainEvent event) {
    final execution = _mapExecutionEvent(event);
    if (execution != null) return execution;

    final occurrence = _mapOccurrenceEvent(event);
    if (occurrence != null) return occurrence;

    final contract = _mapContractEvent(event);
    if (contract != null) return contract;

    final sanction = _mapSanctionEvent(event);
    if (sanction != null) return sanction;

    final justification = _mapJustificationEvent(event);
    if (justification != null) return justification;

    return _mapUnknownEvent(event);
  }

  // ── Execution Event Mappers ───────────────────────────────────────────────

  static SlaLedgerEntry? _mapExecutionEvent(DomainEvent event) {
    if (event is ExecutionBoundEvent) return _mapExecutionBound(event);
    if (event is NoShowDeclaredEvent) return _mapNoShowDeclared(event);
    if (event is EvidenceGapDeclaredEvent) {
      return _mapEvidenceGapDeclared(event);
    }
    if (event is ContractualPlanDeclaredEvent) return _mapPlanDeclared(event);
    if (event is TransitStartedEvent) return _mapTransitStarted(event);
    if (event is CompletedWithGapsEvent) return _mapCompletedWithGaps(event);
    if (event is ExecutionInhibitedEvent) return _mapExecutionInhibited(event);
    return null;
  }

  static SlaLedgerEntry _mapExecutionBound(ExecutionBoundEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'EXECUTION_BOUND',
      operatorId: 'SYSTEM',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'vehicle_id': event.vehicleId,
        'binding_timestamp_utc': event.bindingTimestampUtc.toIso8601String(),
        'latitude': event.bindingLatitude,
        'longitude': event.bindingLongitude,
      },
    );
  }

  static SlaLedgerEntry _mapNoShowDeclared(NoShowDeclaredEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'NO_SHOW_DECLARED',
      operatorId: 'SYSTEM',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {'declared_at_utc': event.declaredAtUtc.toIso8601String()},
    );
  }

  static SlaLedgerEntry _mapEvidenceGapDeclared(
    EvidenceGapDeclaredEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'EVIDENCE_GAP_DECLARED',
      operatorId: 'SYSTEM',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {'declared_at_utc': event.declaredAtUtc.toIso8601String()},
    );
  }

  static SlaLedgerEntry _mapPlanDeclared(ContractualPlanDeclaredEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'PLAN_DECLARED',
      operatorId: event.declaredByUserId,
      setId: null,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'plan_declaration_id': event.planDeclarationId,
        'declared_at_utc': event.declaredAtUtc.toIso8601String(),
        'declared_by_user_id': event.declaredByUserId,
        'total_services': event.totalServicesDeclared,
      },
    );
  }

  static SlaLedgerEntry _mapTransitStarted(TransitStartedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'TRANSIT_STARTED',
      operatorId: 'SYSTEM',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'started_at_utc': event.startedAtUtc.toIso8601String(),
        'source': event.source,
      },
    );
  }

  static SlaLedgerEntry _mapCompletedWithGaps(CompletedWithGapsEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'COMPLETED_WITH_GAPS',
      operatorId: 'SYSTEM',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {'completed_at_utc': event.completedAtUtc.toIso8601String()},
    );
  }

  static SlaLedgerEntry _mapExecutionInhibited(ExecutionInhibitedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'EXECUTION_INHIBITED',
      operatorId: 'SYSTEM',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {'reason': event.reason},
    );
  }

  // ── Occurrence Event Mappers ───────────────────────────────────────────────

  static SlaLedgerEntry? _mapOccurrenceEvent(DomainEvent event) {
    if (event is OccurrenceRegisteredEvidence) {
      return _mapOccurrenceRegistered(event);
    }
    if (event is TripInterruptedEvidence) return _mapTripInterrupted(event);
    if (event is TripCancelledEvidence) return _mapTripCancelled(event);
    return null;
  }

  static SlaLedgerEntry _mapOccurrenceRegistered(
    OccurrenceRegisteredEvidence event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'OCCURRENCE_REGISTERED',
      operatorId: event.operatorId,
      setId: event.tripId,
      contractId: 'N/A',
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'vehicle_id': event.vehicleId,
        'operator_id': event.operatorId,
        'occurrence_type': event.occurrenceType,
        'notes': event.notes,
        'metadata': event.metadata,
      },
    );
  }

  static SlaLedgerEntry _mapTripInterrupted(TripInterruptedEvidence event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'TRIP_INTERRUPTED',
      operatorId: event.operatorId,
      setId: event.tripId,
      contractId: 'N/A',
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'vehicle_id': event.vehicleId,
        'operator_id': event.operatorId,
        'reason': event.reason,
      },
    );
  }

  static SlaLedgerEntry _mapTripCancelled(TripCancelledEvidence event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'TRIP_CANCELLED',
      operatorId: event.operatorId,
      setId: event.tripId,
      contractId: 'N/A',
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'vehicle_id': event.vehicleId,
        'operator_id': event.operatorId,
        'reason': event.reason,
      },
    );
  }

  // ── Contract Event Mappers ──────────────────────────────────────────────────

  static SlaLedgerEntry? _mapContractEvent(DomainEvent event) {
    if (event is ContractCreatedEvent) return _mapContractCreated(event);
    if (event is ContractActivatedEvent) return _mapContractActivated(event);
    if (event is ContractClosedEvent) return _mapContractClosed(event);
    if (event is ContractSubmittedForApprovalEvent) {
      return _mapContractSubmittedForApproval(event);
    }
    if (event is ContractAcceptedByContractorEvent) {
      return _mapContractAcceptedByContractor(event);
    }
    return null;
  }

  static SlaLedgerEntry _mapContractCreated(ContractCreatedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'CONTRACT_CREATED',
      operatorId: 'SYSTEM',
      setId: null,
      contractId: event.contractId,
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'name': event.name,
        'contractor_name': event.contractorName,
        'valid_from_utc': event.validFromUtc.toIso8601String(),
        'valid_until_utc': event.validUntilUtc.toIso8601String(),
      },
    );
  }

  static SlaLedgerEntry _mapContractActivated(ContractActivatedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'CONTRACT_ACTIVATED',
      operatorId: 'SYSTEM',
      setId: null,
      contractId: event.contractId,
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {'activated_at_utc': event.activatedAtUtc.toIso8601String()},
    );
  }

  static SlaLedgerEntry _mapContractClosed(ContractClosedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'CONTRACT_CLOSED',
      operatorId: event.closedByUserId,
      setId: null,
      contractId: event.contractId,
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'closed_at_utc': event.closedAtUtc.toIso8601String(),
        'closed_by_user_id': event.closedByUserId,
        'reason': event.reason,
      },
    );
  }

  static SlaLedgerEntry _mapContractSubmittedForApproval(
    ContractSubmittedForApprovalEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'CONTRACT_SUBMITTED_FOR_APPROVAL',
      operatorId: 'SYSTEM',
      setId: null,
      contractId: event.contractId,
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'submitted_at_utc': event.submittedAtUtc.toIso8601String(),
        'review_token': event.reviewToken,
      },
    );
  }

  static SlaLedgerEntry _mapContractAcceptedByContractor(
    ContractAcceptedByContractorEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'CONTRACT_ACCEPTED_BY_CONTRACTOR',
      operatorId: 'CONTRACTOR',
      setId: null,
      contractId: event.contractId,
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'accepted_at_utc': event.acceptedAtUtc.toIso8601String(),
        'review_token': event.reviewToken,
      },
    );
  }

  // ── Sanction Event Mappers ──────────────────────────────────────────────────

  static SlaLedgerEntry? _mapSanctionEvent(DomainEvent event) {
    if (event is SanctionRecommendedEvent) {
      return _mapSanctionRecommended(event);
    }
    if (event is SanctionAppliedEvent) return _mapSanctionApplied(event);
    if (event is SanctionRejectedEvent) return _mapSanctionRejected(event);
    if (event is SanctionDisputedEvent) return _mapSanctionDisputed(event);
    if (event is DisputeAcceptedEvent) return _mapDisputeAccepted(event);
    if (event is DisputeOverturnedEvent) return _mapDisputeOverturned(event);
    if (event is DisputeRetractedEvent) return _mapDisputeRetracted(event);
    return null;
  }

  static SlaLedgerEntry _mapSanctionRecommended(
    SanctionRecommendedEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'SANCTION_RECOMMENDED',
      operatorId: 'SYSTEM',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'verdict_evidence': event.verdictEvidence.toJson(),
        if (event.vehiclePlate != null) 'vehicle_plate': event.vehiclePlate,
        if (event.operatorName != null) 'operator_name': event.operatorName,
      },
    );
  }

  static SlaLedgerEntry _mapSanctionApplied(SanctionAppliedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'VERDICT_SEALED',
      operatorId: event.approvedByUserId,
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'queue_entry_id': event.queueEntryId,
        'approved_by_user_id': event.approvedByUserId,
        'actor_email': event.actorEmail,
        'verdict_evidence': event.verdictEvidence.toJson(),
      },
    );
  }

  static SlaLedgerEntry _mapSanctionRejected(SanctionRejectedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'VERDICT_REFUSED',
      operatorId: event.rejectedByUserId,
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'queue_entry_id': event.queueEntryId,
        'rejected_by_user_id': event.rejectedByUserId,
        'actor_email': event.actorEmail,
        'rejection_reason': event.rejectionReason,
        'verdict_evidence': event.verdictEvidence.toJson(),
      },
    );
  }

  static SlaLedgerEntry _mapSanctionDisputed(SanctionDisputedEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'SANCTION_DISPUTED',
      operatorId: 'CONTRACTOR',
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'queue_entry_id': event.queueEntryId,
        'verdict_evidence': event.verdictEvidence.toJson(),
      },
    );
  }

  static SlaLedgerEntry _mapDisputeAccepted(DisputeAcceptedEvent event) {
    return _mapDisputeResolution(event, 'DISPUTE_ACCEPTED');
  }

  static SlaLedgerEntry _mapDisputeOverturned(DisputeOverturnedEvent event) {
    return _mapDisputeResolution(event, 'DISPUTE_OVERTURNED');
  }

  static SlaLedgerEntry _mapDisputeRetracted(DisputeRetractedEvent event) {
    return _mapDisputeResolution(event, 'DISPUTE_RETRACTED');
  }

  // ── Justification Event Mappers ─────────────────────────────────────────────

  static SlaLedgerEntry? _mapJustificationEvent(DomainEvent event) {
    if (event is JustificationSubmittedEvent) {
      return _mapJustificationSubmitted(event);
    }
    if (event is JustificationApprovedEvent) {
      return _mapJustificationApproved(event);
    }
    if (event is JustificationRejectedEvent) {
      return _mapJustificationRejected(event);
    }
    if (event is SLAJustificationSubmittedEvent) {
      return _mapSLAJustificationSubmitted(event);
    }
    if (event is SLAJustificationExpiredEvent) {
      return _mapSLAJustificationExpired(event);
    }
    return null;
  }

  static SlaLedgerEntry _mapJustificationSubmitted(
    JustificationSubmittedEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'JUSTIFICATION_SUBMITTED',
      operatorId: event.actorUserId,
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'justification_id': event.justificationId,
        'actor_id': event.actorUserId,
        'set_id': event.setId,
        'caller_user_id': event.actorUserId,
        'evidence_hashes': event.evidenceHashes,
      },
    );
  }

  static SlaLedgerEntry _mapJustificationApproved(
    JustificationApprovedEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'JUSTIFICATION_APPROVED',
      operatorId: event.actorUserId,
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'justification_id': event.justificationId,
        'actor_id': event.actorUserId,
        'actor_email': event.actorEmail,
      },
    );
  }

  static SlaLedgerEntry _mapJustificationRejected(
    JustificationRejectedEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'JUSTIFICATION_REJECTED',
      operatorId: event.actorUserId,
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'justification_id': event.justificationId,
        'actor_id': event.actorUserId,
        'actor_email': event.actorEmail,
      },
    );
  }

  static SlaLedgerEntry _mapSLAJustificationSubmitted(
    SLAJustificationSubmittedEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'SLA_JUSTIFICATION_SUBMITTED',
      operatorId: event.actorUserId,
      setId: null,
      contractId: 'N/A',
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'justification_id': event.justificationId,
        'vehicle_id': event.vehicleId,
        'occurrence_timestamp': event.occurrenceTimestamp.toIso8601String(),
        'actor_user_id': event.actorUserId,
        'evidence_hashes': event.evidenceHashes,
      },
    );
  }

  static SlaLedgerEntry _mapSLAJustificationExpired(
    SLAJustificationExpiredEvent event,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'SLA_JUSTIFICATION_EXPIRED',
      operatorId: 'SYSTEM',
      setId: null,
      contractId: 'N/A',
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'justification_id': event.justificationId,
        'vehicle_id': event.vehicleId,
        'occurrence_timestamp': event.occurrenceTimestamp.toIso8601String(),
      },
    );
  }

  // ── Helper Utility Mappers ─────────────────────────────────────────────────

  static SlaLedgerEntry _mapDisputeResolution(
    DisputeResolvedEvent event,
    String type,
  ) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: type,
      operatorId: event.resolvedByUserId,
      setId: event.setId,
      contractId: event.contractId,
      planVersion: event.planVersion,
      occurredAtUtc: event.occurredAtUtc,
      payload: {
        'queue_entry_id': event.queueEntryId,
        'resolved_by_user_id': event.resolvedByUserId,
        'actor_email': event.actorEmail,
        'resolution_reason': event.resolutionReason,
        'verdict_evidence': event.verdictEvidence.toJson(),
      },
    );
  }

  static SlaLedgerEntry _mapUnknownEvent(DomainEvent event) {
    return SlaLedgerEntry(
      organizationId: event.organizationId,
      type: 'UNKNOWN_EVENT',
      operatorId: 'SYSTEM',
      contractId: 'unknown',
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {'raw_event_type': event.runtimeType.toString()},
    );
  }
}
