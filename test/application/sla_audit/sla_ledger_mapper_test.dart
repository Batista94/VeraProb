import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_event.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';

// Stub unknown event for fallback coverage
class _UnknownEvent extends DomainEvent {
  const _UnknownEvent({
    required super.organizationId,
    required super.occurredAtUtc,
  });
}

void main() {
  group('SlaLedgerMapper - EvidenceEvents Verification', () {
    final DateTime now = DateTime.now().toUtc();

    test(
      'OccurrenceRegisteredEvidence maps gracefully without validation faults',
      () {
        final evidence = OccurrenceRegisteredEvidence(
          organizationId: 'org-1',
          occurredAtUtc: now,
          tripId: 'trip-789',
          vehicleId: 'veh-001',
          operatorId: 'operator-ab',
          occurrenceType: 'Acidente',
          notes: 'Colisão lateral',
          metadata: {'severity': 'high'},
        );

        final entry = SlaLedgerMapper.mapToEntry(evidence);

        expect(entry.type, 'OCCURRENCE_REGISTERED');
        expect(entry.setId, 'trip-789');
        expect(entry.contractId, 'N/A');
        expect(entry.planVersion, 0);
        expect(entry.occurredAtUtc, now);

        expect(entry.payload['vehicle_id'], 'veh-001');
        expect(entry.payload['operator_id'], 'operator-ab');
        expect(entry.payload['occurrence_type'], 'Acidente');
        expect(entry.payload['notes'], 'Colisão lateral');
        expect(entry.payload['metadata'], {'severity': 'high'});
      },
    );

    test('TripInterruptedEvidence maps gracefully', () {
      final evidence = TripInterruptedEvidence(
        organizationId: 'org-1',
        occurredAtUtc: now,
        tripId: 'trip-789',
        vehicleId: 'veh-001',
        operatorId: 'operator-cd',
        reason: 'Pneu Furado',
      );

      final entry = SlaLedgerMapper.mapToEntry(evidence);

      expect(entry.type, 'TRIP_INTERRUPTED');
      expect(entry.setId, 'trip-789');
      expect(entry.contractId, 'N/A');
      expect(entry.planVersion, 0);
      expect(entry.occurredAtUtc, now);

      expect(entry.payload['vehicle_id'], 'veh-001');
      expect(entry.payload['operator_id'], 'operator-cd');
      expect(entry.payload['reason'], 'Pneu Furado');
    });

    test('TripCancelledEvidence maps gracefully', () {
      final evidence = TripCancelledEvidence(
        organizationId: 'org-1',
        occurredAtUtc: now,
        tripId: 'trip-789',
        vehicleId: null,
        operatorId: 'operator-ef',
        reason: 'Problemas Mecânicos',
      );

      final entry = SlaLedgerMapper.mapToEntry(evidence);

      expect(entry.type, 'TRIP_CANCELLED');
      expect(entry.setId, 'trip-789');
      expect(entry.contractId, 'N/A');
      expect(entry.planVersion, 0);
      expect(entry.occurredAtUtc, now);

      expect(entry.payload['vehicle_id'], isNull);
      expect(entry.payload['operator_id'], 'operator-ef');
      expect(entry.payload['reason'], 'Problemas Mecânicos');
    });
  });

  group('SlaLedgerMapper - EvidenceGapDeclaredEvent', () {
    final DateTime now = DateTime.now().toUtc();

    test('EvidenceGapDeclaredEvent maps to EVIDENCE_GAP_DECLARED entry', () {
      final event = EvidenceGapDeclaredEvent(
        organizationId: 'org-1',
        occurredAtUtc: now,
        setId: 'set-abc',
        contractId: 'contract-99',
        planVersion: 2,
        declaredAtUtc: now,
      );

      final entry = SlaLedgerMapper.mapToEntry(event);

      expect(entry.type, 'EVIDENCE_GAP_DECLARED');
      expect(entry.organizationId, 'org-1');
      expect(entry.setId, 'set-abc');
      expect(entry.contractId, 'contract-99');
      expect(entry.planVersion, 2);
      expect(entry.operatorId, 'SYSTEM');
      expect(entry.occurredAtUtc, now);
      expect(entry.payload['declared_at_utc'], now.toIso8601String());
    });
  });

  group('SlaLedgerMapper - SanctionDisputedEvent', () {
    final DateTime now = DateTime.now().toUtc();

    VerdictEvidence buildEvidence() => VerdictEvidence.create(
          clauseRef: 'VEL-01',
          ruleId: 'rule-speed-v1',
          ruleVersion: 1,
          primaryEvidenceLat: -23.5505,
          primaryEvidenceLng: -46.6333,
          primaryEvidenceTimestampUtc: now,
          deltaValue: 8.5,
          thresholdValue: 80.0,
          fineCents: const Money(150000),
          confidenceScore: 95,
        );

    test('SanctionDisputedEvent maps to SANCTION_DISPUTED entry', () {
      final evidence = buildEvidence();
      final event = SanctionDisputedEvent(
        organizationId: 'org-2',
        occurredAtUtc: now,
        setId: 'set-dispute-1',
        contractId: 'contract-55',
        planVersion: 3,
        queueEntryId: 'queue-entry-999',
        verdictEvidence: evidence,
      );

      final entry = SlaLedgerMapper.mapToEntry(event);

      expect(entry.type, 'SANCTION_DISPUTED');
      expect(entry.organizationId, 'org-2');
      expect(entry.operatorId, 'CONTRACTOR');
      expect(entry.setId, 'set-dispute-1');
      expect(entry.contractId, 'contract-55');
      expect(entry.planVersion, 3);
      expect(entry.occurredAtUtc, now);
      expect(entry.payload['queue_entry_id'], 'queue-entry-999');
      expect(entry.payload['verdict_evidence'], isA<Map<String, dynamic>>());
    });
  });

  group('SlaLedgerMapper - unknown event fallback', () {
    final DateTime now = DateTime.now().toUtc();

    test('unrecognised event maps to UNKNOWN_EVENT entry', () {
      final event = _UnknownEvent(
        organizationId: 'org-unknown',
        occurredAtUtc: now,
      );

      final entry = SlaLedgerMapper.mapToEntry(event);

      expect(entry.type, 'UNKNOWN_EVENT');
      expect(entry.organizationId, 'org-unknown');
      expect(entry.operatorId, 'SYSTEM');
      expect(entry.contractId, 'unknown');
      expect(entry.planVersion, 0);
      expect(entry.occurredAtUtc, now);
      expect(entry.payload['raw_event_type'], isA<String>());
    });
  });
}
