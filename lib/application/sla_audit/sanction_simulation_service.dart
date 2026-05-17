import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'sla_ledger_mapper.dart';

/// Service used ONLY during development to inject
/// artificial sanctions into the review queue for testing Phase 9.
class SanctionSimulationService {
  final SlaAuditLedgerRepository _ledger;
  final ContractRepository _contracts;
  final IDateTimeProvider _clock;

  SanctionSimulationService({
    required SlaAuditLedgerRepository ledger,
    required ContractRepository contracts,
    required IDateTimeProvider clock,
  }) : _ledger = ledger,
       _contracts = contracts,
       _clock = clock;

  Future<void> simulateSpeedViolation({
    required String organizationId,
    required String vehiclePlate,
    double speed = 88.5, // Physical Metric - Double Required
    double limit = 80.0, // Physical Metric - Double Required
  }) async {
    try {
      final now = _clock.nowUtc();
      final setId = 'sim-set-${const Uuid().v4().substring(0, 8)}';

      // 0. Find a valid contract
      final contracts = await _contracts.findByOrganization(organizationId);
      if (contracts.isEmpty) {
        throw const DomainException(
          'Nenhum contrato encontrado para esta organização. Crie um contrato primeiro.',
        );
      }
      final contractId = contracts.first.id;

      final evidence = VerdictEvidence.create(
        clauseRef: 'VEL-01',
        ruleId: 'rule-speed-v1',
        ruleVersion: 1,
        primaryEvidenceLat: -23.5505 + (_clock.nowUtc().millisecond / 100000),
        primaryEvidenceLng: -46.6333 + (_clock.nowUtc().millisecond / 100000),
        primaryEvidenceTimestampUtc: now,
        deltaValue: speed - limit,
        thresholdValue: limit,
        fineCents: const Money(150000), // R$ 1.500,00
        confidenceScore: 99,
      );

      final event = SanctionRecommendedEvent(
        organizationId: organizationId,
        occurredAtUtc: now,
        setId: setId,
        contractId: contractId,
        planVersion: 1,
        verdictEvidence: evidence,
      );

      // 1. Append to ledger (audit trail)
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);

      // 2. Enqueue for review (Fila Auditora)
      // INV-24/INV-23: Rely on the DB trigger `tr_ledger_to_review_queue`
      // which auto-populates sanction_review_queue when a SANCTION_RECOMMENDED
      // entry is added to the ledger. Manual insertion here violates RLS for non-system roles.
      // We just need to wait a small moment for the trigger to finish before refreshing the UI.
    } catch (e) {
      // Log for dev debugging
      debugPrint('Error in SanctionSimulationService: $e');
      rethrow;
    }
  }

  Future<void> seedActiveSanctions({required String organizationId}) async {
    try {
      await simulateSpeedViolation(
        organizationId: organizationId,
        vehiclePlate: 'TEST-0001',
        speed: 92.0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await simulateSpeedViolation(
        organizationId: organizationId,
        vehiclePlate: 'TEST-0002',
        speed: 84.5,
      );
    } catch (e) {
      debugPrint('Error in seedActiveSanctions: $e');
    }
  }
}
