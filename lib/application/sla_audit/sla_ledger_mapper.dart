import '../../domain/sla_audit/contractual_plan_declared_event.dart';
import '../../domain/sla_audit/domain_event.dart';
import '../../domain/sla_audit/execution_events.dart';
import '../../domain/sla_audit/sla_ledger_entry.dart';

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
        type: 'EXECUTION_BOUND',
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
        type: 'NO_SHOW_DECLARED',
        setId: event.setId,
        contractId: event.contractId,
        planVersion: event.planVersion,
        occurredAtUtc: event.occurredAtUtc,
        payload: {'declared_at_utc': event.declaredAtUtc.toIso8601String()},
      );
    }

    if (event is EvidenceGapDeclaredEvent) {
      return SlaLedgerEntry(
        type: 'EVIDENCE_GAP_DECLARED',
        setId: event.setId,
        contractId: event.contractId,
        planVersion: event.planVersion,
        occurredAtUtc: event.occurredAtUtc,
        payload: {'declared_at_utc': event.declaredAtUtc.toIso8601String()},
      );
    }
    if (event is ContractualPlanDeclaredEvent) {
      return SlaLedgerEntry(
        type: 'PLAN_DECLARED',
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
        type: 'OCCURRENCE_REGISTERED',
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
        type: 'TRIP_INTERRUPTED',
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
        type: 'TRIP_CANCELLED',
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

    // Generic fallback for unknown events
    return SlaLedgerEntry(
      type: 'UNKNOWN_EVENT',
      contractId: 'unknown',
      planVersion: 0,
      occurredAtUtc: event.occurredAtUtc,
      payload: {'raw_event_type': event.runtimeType.toString()},
    );
  }
}
