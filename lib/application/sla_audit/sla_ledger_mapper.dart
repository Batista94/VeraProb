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
    if (event is ExecutionBoundEvent) {
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

    if (event is NoShowDeclaredEvent) {
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

    if (event is EvidenceGapDeclaredEvent) {
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
    if (event is ContractualPlanDeclaredEvent) {
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

    if (event is OccurrenceRegisteredEvidence) {
      return SlaLedgerEntry(
        organizationId: event.organizationId,
        type: 'OCCURRENCE_REGISTERED',
        operatorId: event.operatorId,
        setId: event.tripId,
        contractId: 'N/A', // Set later when merged or queried contextually
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

    if (event is TripInterruptedEvidence) {
      return SlaLedgerEntry(
        organizationId: event.organizationId,
        type: 'TRIP_INTERRUPTED',
        operatorId: event.operatorId,
        setId: event.tripId,
        contractId: 'N/A', // Set later when merged or queried contextually
        planVersion: 0,
        occurredAtUtc: event.occurredAtUtc,
        payload: {
          'vehicle_id': event.vehicleId,
          'operator_id': event.operatorId,
          'reason': event.reason,
        },
      );
    }

    if (event is TripCancelledEvidence) {
      return SlaLedgerEntry(
        organizationId: event.organizationId,
        type: 'TRIP_CANCELLED',
        operatorId: event.operatorId,
        setId: event.tripId,
        contractId: 'N/A', // Set later when merged or queried contextually
        planVersion: 0,
        occurredAtUtc: event.occurredAtUtc,
        payload: {
          'vehicle_id': event.vehicleId,
          'operator_id': event.operatorId,
          'reason': event.reason,
        },
      );
    }

    if (event is ContractCreatedEvent) {
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

    if (event is ContractActivatedEvent) {
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

    if (event is ContractClosedEvent) {
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

    if (event is ContractSubmittedForApprovalEvent) {
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

    if (event is ContractAcceptedByContractorEvent) {
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

    if (event is SanctionRecommendedEvent) {
      return SlaLedgerEntry(
        organizationId: event.organizationId,
        type: 'SANCTION_RECOMMENDED',
        operatorId: 'SYSTEM',
        setId: event.setId,
        contractId: event.contractId,
        planVersion: event.planVersion,
        occurredAtUtc: event.occurredAtUtc,
        payload: {'verdict_evidence': event.verdictEvidence.toJson()},
      );
    }

    if (event is SanctionAppliedEvent) {
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

    if (event is SanctionRejectedEvent) {
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

    if (event is SanctionDisputedEvent) {
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

    if (event is JustificationSubmittedEvent) {
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

    if (event is JustificationApprovedEvent) {
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

    if (event is JustificationRejectedEvent) {
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

    // ── CX-05: Vehicle-Event Level SLA Justification Events ──────────────

    if (event is SLAJustificationSubmittedEvent) {
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
          'event_timestamp': event.eventTimestamp.toIso8601String(),
          'actor_user_id': event.actorUserId,
          'evidence_hashes': event.evidenceHashes,
        },
      );
    }

    if (event is SLAJustificationExpiredEvent) {
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
          'event_timestamp': event.eventTimestamp.toIso8601String(),
        },
      );
    }

    // Generic fallback for unknown events
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
