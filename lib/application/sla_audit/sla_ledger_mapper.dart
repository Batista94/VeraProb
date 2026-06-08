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
///
/// Responsibilities are delegated to private sub-mappers grouped by domain:
/// - [_SlaExecutionEventMapper]  — execution lifecycle
/// - [_SlaOccurrenceEventMapper] — occurrence evidence
/// - [_SlaContractEventMapper]   — contract lifecycle
/// - [_SlaSanctionEventMapper]   — sanctions & disputes
/// - [_SlaJustificationEventMapper] — justifications
class SlaLedgerMapper {
  /// Maps a [DomainEvent] to its forensic [SlaLedgerEntry].
  static SlaLedgerEntry mapToEntry(DomainEvent event) {
    final execution = _SlaExecutionEventMapper.map(event);
    if (execution != null) return execution;

    final occurrence = _SlaOccurrenceEventMapper.map(event);
    if (occurrence != null) return occurrence;

    final contract = _SlaContractEventMapper.map(event);
    if (contract != null) return contract;

    final sanction = _SlaSanctionEventMapper.map(event);
    if (sanction != null) return sanction;

    final justification = _SlaJustificationEventMapper.map(event);
    if (justification != null) return justification;

    return _mapUnknownEvent(event);
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

// ── Execution Event Mapper ────────────────────────────────────────────────────

class _SlaExecutionEventMapper {
  static SlaLedgerEntry? map(DomainEvent event) {
    if (event is ExecutionBoundEvent) return _bound(event);
    if (event is NoShowDeclaredEvent) return _noShow(event);
    if (event is EvidenceGapDeclaredEvent) return _evidenceGap(event);
    if (event is ContractualPlanDeclaredEvent) return _planDeclared(event);
    if (event is TransitStartedEvent) return _transitStarted(event);
    if (event is CompletedWithGapsEvent) return _completedWithGaps(event);
    if (event is ExecutionInhibitedEvent) return _executionInhibited(event);
    return null;
  }

  static SlaLedgerEntry _bound(ExecutionBoundEvent event) {
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

  static SlaLedgerEntry _noShow(NoShowDeclaredEvent event) {
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

  static SlaLedgerEntry _evidenceGap(EvidenceGapDeclaredEvent event) {
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

  static SlaLedgerEntry _planDeclared(ContractualPlanDeclaredEvent event) {
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

  static SlaLedgerEntry _transitStarted(TransitStartedEvent event) {
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

  static SlaLedgerEntry _completedWithGaps(CompletedWithGapsEvent event) {
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

  static SlaLedgerEntry _executionInhibited(ExecutionInhibitedEvent event) {
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
}

// ── Occurrence Event Mapper ───────────────────────────────────────────────────

class _SlaOccurrenceEventMapper {
  static SlaLedgerEntry? map(DomainEvent event) {
    if (event is OccurrenceRegisteredEvidence) return _registered(event);
    if (event is TripInterruptedEvidence) return _interrupted(event);
    if (event is TripCancelledEvidence) return _cancelled(event);
    return null;
  }

  static SlaLedgerEntry _registered(OccurrenceRegisteredEvidence event) {
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

  static SlaLedgerEntry _interrupted(TripInterruptedEvidence event) {
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

  static SlaLedgerEntry _cancelled(TripCancelledEvidence event) {
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
}

// ── Contract Event Mapper ─────────────────────────────────────────────────────

class _SlaContractEventMapper {
  static SlaLedgerEntry? map(DomainEvent event) {
    if (event is ContractCreatedEvent) return _created(event);
    if (event is ContractActivatedEvent) return _activated(event);
    if (event is ContractClosedEvent) return _closed(event);
    if (event is ContractSubmittedForApprovalEvent) {
      return _submittedForApproval(event);
    }
    if (event is ContractAcceptedByContractorEvent) {
      return _acceptedByContractor(event);
    }
    return null;
  }

  static SlaLedgerEntry _created(ContractCreatedEvent event) {
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

  static SlaLedgerEntry _activated(ContractActivatedEvent event) {
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

  static SlaLedgerEntry _closed(ContractClosedEvent event) {
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

  static SlaLedgerEntry _submittedForApproval(
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

  static SlaLedgerEntry _acceptedByContractor(
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
}

// ── Sanction & Dispute Event Mapper ───────────────────────────────────────────

class _SlaSanctionEventMapper {
  static SlaLedgerEntry? map(DomainEvent event) {
    if (event is SanctionRecommendedEvent) return _recommended(event);
    if (event is SanctionAppliedEvent) return _applied(event);
    if (event is SanctionRejectedEvent) return _rejected(event);
    if (event is SanctionDisputedEvent) return _disputed(event);
    if (event is DisputeAcceptedEvent) {
      return _resolution(event, 'DISPUTE_ACCEPTED');
    }
    if (event is DisputeOverturnedEvent) {
      return _resolution(event, 'DISPUTE_OVERTURNED');
    }
    if (event is DisputeRetractedEvent) {
      return _resolution(event, 'DISPUTE_RETRACTED');
    }
    return null;
  }

  static SlaLedgerEntry _recommended(SanctionRecommendedEvent event) {
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

  static SlaLedgerEntry _applied(SanctionAppliedEvent event) {
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

  static SlaLedgerEntry _rejected(SanctionRejectedEvent event) {
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

  static SlaLedgerEntry _disputed(SanctionDisputedEvent event) {
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

  static SlaLedgerEntry _resolution(DisputeResolvedEvent event, String type) {
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
}

// ── Justification Event Mapper ────────────────────────────────────────────────

class _SlaJustificationEventMapper {
  static SlaLedgerEntry? map(DomainEvent event) {
    if (event is JustificationSubmittedEvent) return _submitted(event);
    if (event is JustificationApprovedEvent) return _approved(event);
    if (event is JustificationRejectedEvent) return _rejected(event);
    if (event is SLAJustificationSubmittedEvent) return _slaSubmitted(event);
    if (event is SLAJustificationExpiredEvent) return _slaExpired(event);
    return null;
  }

  static SlaLedgerEntry _submitted(JustificationSubmittedEvent event) {
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

  static SlaLedgerEntry _approved(JustificationApprovedEvent event) {
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

  static SlaLedgerEntry _rejected(JustificationRejectedEvent event) {
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

  static SlaLedgerEntry _slaSubmitted(SLAJustificationSubmittedEvent event) {
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

  static SlaLedgerEntry _slaExpired(SLAJustificationExpiredEvent event) {
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
}
