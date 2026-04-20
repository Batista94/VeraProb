import 'package:veraprob/application/ports/contractual_event_port.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'sla_ledger_mapper.dart';

/// Transport module implementation of [ContractualEventPort].
///
/// Encapsulates all SLA ledger and mapper knowledge so that Core services
/// never need to import module-specific types.
class SlaContractualEventPort implements ContractualEventPort {
  final SlaAuditLedgerRepository _ledgerRepo;

  SlaContractualEventPort(this._ledgerRepo);

  @override
  Future<void> dispatchTripInterrupted({
    required String organizationId,
    required String tripId,
    String? vehicleId,
    required String operatorId,
    String? reason,
    required DateTime occurredAtUtc,
  }) async {
    final evidence = TripInterruptedEvidence(
      organizationId: organizationId,
      occurredAtUtc: occurredAtUtc,
      tripId: tripId,
      vehicleId: vehicleId,
      operatorId: operatorId,
      reason: reason,
    );
    await _ledgerRepo.append(SlaLedgerMapper.mapToEntry(evidence));
  }

  @override
  Future<void> dispatchTripCancelled({
    required String organizationId,
    required String tripId,
    String? vehicleId,
    required String operatorId,
    String? reason,
    required DateTime occurredAtUtc,
  }) async {
    final evidence = TripCancelledEvidence(
      organizationId: organizationId,
      occurredAtUtc: occurredAtUtc,
      tripId: tripId,
      vehicleId: vehicleId,
      operatorId: operatorId,
      reason: reason,
    );
    await _ledgerRepo.append(SlaLedgerMapper.mapToEntry(evidence));
  }

  @override
  Future<void> dispatchOccurrenceRegistered({
    required String organizationId,
    required String tripId,
    String? vehicleId,
    required String operatorId,
    required String occurrenceType,
    String? notes,
    required Map<String, dynamic> metadata,
    required DateTime occurredAtUtc,
  }) async {
    final evidence = OccurrenceRegisteredEvidence(
      organizationId: organizationId,
      occurredAtUtc: occurredAtUtc,
      tripId: tripId,
      vehicleId: vehicleId,
      operatorId: operatorId,
      occurrenceType: occurrenceType,
      notes: notes,
      metadata: metadata,
    );
    await _ledgerRepo.append(SlaLedgerMapper.mapToEntry(evidence));
  }
}
