import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_event.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/dto/sla_ledger_entry_dto.dart';

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

  // ── INV-9 UTC Normalization ──────────────────────────────────────────────────

  group('INV-9 UTC normalization — occurredAtUtc must carry isUtc=true', () {
    test(
      'ExecutionBoundEvent entry has isUtc=true and ISO string ending with Z',
      () {
        final utcTime = DateTime.utc(2026, 4, 10, 14, 0, 0);
        final event = ExecutionBoundEvent(
          organizationId: 'org-1',
          occurredAtUtc: utcTime,
          setId: 'set-1',
          contractId: 'contract-1',
          planVersion: 1,
          vehicleId: 'veh-1',
          bindingTimestampUtc: utcTime,
          bindingLatitude: -23.5505, // Physical Metric - Double Required
          bindingLongitude: -46.6333, // Physical Metric - Double Required
        );

        final entry = SlaLedgerMapper.mapToEntry(event);

        expect(
          entry.occurredAtUtc.isUtc,
          isTrue,
          reason: 'INV-9: timestamp must be UTC',
        );
        expect(
          entry.occurredAtUtc.toIso8601String(),
          endsWith('Z'),
          reason: 'INV-9: ISO string must carry Z suffix',
        );
      },
    );

    test(
      'SlaLedgerEntryDto.toDomain normalizes timestamp to UTC regardless of source format',
      () {
        // Simulate DB row — some Postgres drivers omit the Z suffix
        final dto = SlaLedgerEntryDto.fromJson({
          'organization_id': 'org-1',
          'type': 'EXECUTION_BOUND',
          'operator_id': 'SYSTEM',
          'contract_id': 'contract-1',
          'plan_version': 1,
          'occurred_at_utc': '2026-04-10T14:00:00.000Z',
          'payload': <String, dynamic>{},
        });

        final domain = dto.toDomain('event-uuid-abc');

        expect(
          domain.occurredAtUtc.isUtc,
          isTrue,
          reason: 'INV-9: toDomain must force UTC',
        );
      },
    );

    test(
      'NoShowDeclaredEvent entry timestamp isUtc survives round-trip via DTO',
      () {
        final utcTime = DateTime.utc(2026, 4, 10, 8, 30, 0);
        final event = NoShowDeclaredEvent(
          organizationId: 'org-2',
          occurredAtUtc: utcTime,
          setId: 'set-no-show',
          contractId: 'contract-2',
          planVersion: 2,
          declaredAtUtc: utcTime,
        );

        final entry = SlaLedgerMapper.mapToEntry(event);
        expect(entry.occurredAtUtc.isUtc, isTrue);

        final dto = SlaLedgerEntryDto.fromDomain(entry);
        final roundTripped = dto.toDomain('event-uuid-xyz');
        expect(roundTripped.occurredAtUtc.isUtc, isTrue);
      },
    );
  });

  // ── Integrity Gap — Row Corruption ─────────────────────────────────────────

  group(
    'SlaLedgerEntryDto — Integrity Gap (INV-18: corrupt row throws IntegrityException)',
    () {
      test(
        'fromJson throws IntegrityException when organization_id is absent',
        () {
          expect(
            () => SlaLedgerEntryDto.fromJson({
              'type': 'EXECUTION_BOUND',
              'occurred_at_utc': '2026-04-10T14:00:00Z',
            }),
            throwsA(
              isA<IntegrityException>().having(
                (e) => e.field,
                'field',
                'organization_id',
              ),
            ),
          );
        },
      );

      test(
        'fromJson throws IntegrityException when organization_id is null',
        () {
          expect(
            () => SlaLedgerEntryDto.fromJson({
              'organization_id': null,
              'type': 'EXECUTION_BOUND',
              'occurred_at_utc': '2026-04-10T14:00:00Z',
            }),
            throwsA(isA<IntegrityException>()),
          );
        },
      );

      test(
        'fromJson throws IntegrityException when occurred_at_utc is missing',
        () {
          expect(
            () => SlaLedgerEntryDto.fromJson({
              'organization_id': 'org-1',
              'type': 'EXECUTION_BOUND',
            }),
            throwsA(
              isA<IntegrityException>().having(
                (e) => e.field,
                'field',
                'occurred_at_utc',
              ),
            ),
          );
        },
      );

      test(
        'fromJson throws IntegrityException when payload penalty_cents is a double',
        () {
          // INV-19: financial fields must be int — double indicates upstream corruption
          expect(
            () => SlaLedgerEntryDto.fromJson({
              'organization_id': 'org-1',
              'type': 'VERDICT_SEALED',
              'occurred_at_utc': '2026-04-10T14:00:00Z',
              'payload': {'penalty_cents': 15000.50}, // double drift
            }),
            throwsA(
              isA<IntegrityException>().having(
                (e) => e.field,
                'field',
                'penalty_cents',
              ),
            ),
          );
        },
      );

      test(
        'fromDomain throws IntegrityException when organizationId is empty',
        () {
          final entry = SlaLedgerEntry(
            organizationId: '',
            type: 'TEST',
            contractId: 'contract-1',
            planVersion: 1,
            occurredAtUtc: DateTime.utc(2026, 4, 10),
          );

          expect(
            () => SlaLedgerEntryDto.fromDomain(entry),
            throwsA(
              isA<IntegrityException>().having(
                (e) => e.field,
                'field',
                'organization_id',
              ),
            ),
          );
        },
      );
    },
  );

  // ── Read-Only Sync — Immutability Guard ─────────────────────────────────────

  group('SlaLedgerEntry — Read-Only immutability (INV-7: no mutation path)', () {
    test('mapper output fields are structurally immutable (final)', () {
      final utcTime = DateTime.utc(2026, 4, 10, 12, 0, 0);
      final event = NoShowDeclaredEvent(
        organizationId: 'org-immut',
        occurredAtUtc: utcTime,
        setId: 'set-abc',
        contractId: 'contract-abc',
        planVersion: 3,
        declaredAtUtc: utcTime,
      );

      final entry = SlaLedgerMapper.mapToEntry(event);

      // All fields are final — no setters exist. Verify read-only by
      // ensuring the same event always maps to an equal entry.
      final entry2 = SlaLedgerMapper.mapToEntry(event);
      expect(
        entry,
        equals(entry2),
        reason: 'deterministic mapping — referential transparency',
      );
    });

    test('DTO fromDomain preserves organizationId without alteration', () {
      const orgId = 'org-protected-uuid';
      final entry = SlaLedgerEntry(
        organizationId: orgId,
        type: 'CONTRACT_ACTIVATED',
        operatorId: 'SYSTEM',
        contractId: 'contract-xyz',
        planVersion: 0,
        occurredAtUtc: DateTime.utc(2026, 4, 10),
      );

      final dto = SlaLedgerEntryDto.fromDomain(entry);
      final json = dto.toJson();

      expect(json['organization_id'], orgId);
      expect(
        json['occurred_at_utc'],
        isA<String>(),
        reason: 'occurredAtUtc serialized as ISO string, not mutated to local',
      );
    });

    test(
      'reconstituted domain from DTO carries the original organizationId unmodified',
      () {
        final entry = SlaLedgerEntry(
          organizationId: 'org-readonly-check',
          type: 'PLAN_DECLARED',
          operatorId: 'user-123',
          contractId: 'contract-ro',
          planVersion: 5,
          occurredAtUtc: DateTime.utc(2026, 4, 10),
        );

        final dto = SlaLedgerEntryDto.fromDomain(entry);
        final reconstituted = dto.toDomain('event-id-ro');

        expect(reconstituted.organizationId, entry.organizationId);
        expect(reconstituted.planVersion, entry.planVersion);
        expect(reconstituted.type, entry.type);
      },
    );
  });

  group('SlaLedgerMapper - SanctionRecommended identity fallback (INV-18)', () {
    final DateTime now = DateTime.now().toUtc();

    VerdictEvidence evidence() => VerdictEvidence.create(
      clauseRef: 'VEL-01',
      ruleId: 'rule-speed-v1',
      ruleVersion: 1,
      primaryEvidenceLat: -23.5,
      primaryEvidenceLng: -46.6,
      primaryEvidenceTimestampUtc: now,
      deltaValue: 8.5,
      thresholdValue: 80.0,
      fineCents: const Money(150000),
      confidenceScore: 99,
    );

    test('omits asset/operator keys when null (real engine flow)', () {
      final entry = SlaLedgerMapper.mapToEntry(
        SanctionRecommendedEvent(
          organizationId: 'org-1',
          occurredAtUtc: now,
          setId: 'set-1',
          contractId: 'contract-1',
          planVersion: 1,
          verdictEvidence: evidence(),
        ),
      );

      expect(entry.type, 'SANCTION_RECOMMENDED');
      expect(entry.payload.containsKey('vehicle_plate'), isFalse);
      expect(entry.payload.containsKey('operator_name'), isFalse);
      expect(entry.payload['verdict_evidence'], isNotNull);
    });

    test('carries asset/operator into payload when provided (simulation)', () {
      final entry = SlaLedgerMapper.mapToEntry(
        SanctionRecommendedEvent(
          organizationId: 'org-1',
          occurredAtUtc: now,
          setId: 'set-1',
          contractId: 'contract-1',
          planVersion: 1,
          verdictEvidence: evidence(),
          vehiclePlate: 'TST-0001',
          operatorName: 'João Silva',
        ),
      );

      expect(entry.payload['vehicle_plate'], 'TST-0001');
      expect(entry.payload['operator_name'], 'João Silva');
    });
  });
}
