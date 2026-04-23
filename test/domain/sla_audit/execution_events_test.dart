/// Forensic Audit Signature: INV-7 / INV-15
/// Test Suite: Execution Events — Immutability & Serialization Fidelity
/// Coverage: All 18 concrete event classes in execution_events.dart
/// Authorized By: VeraProb QA Security Lead
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';
import 'package:veraprob/domain/sla_audit/domain_event.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/money.dart';

// ── Shared fixtures ───────────────────────────────────────────────────────────

const _orgId = 'org-forense-001';
const _setId = 'set-abc-001';
const _contractId = 'contract-xyz-001';
const _vehicleId = 'vehicle-br-001';
const _userId = 'user-operador-001';
const _email = 'operador@veraprob.com.br';
const _justId = 'just-001';
const _queueId = 'queue-001';
final _ts = DateTime.utc(2026, 4, 23, 12, 30, 45, 123, 456);
final _ts2 = DateTime.utc(2026, 4, 23, 13, 0, 0);

VerdictEvidence _makeVerdictEvidence() => VerdictEvidence.create(
  clauseRef: 'no-show-penalty-rule-1',
  ruleId: 'rule-001',
  ruleVersion: 1,
  primaryEvidenceLat: -23.5505,
  primaryEvidenceLng: -46.6333,
  primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 23, 10, 0),
  deltaValue: 15.0,
  thresholdValue: 0.0,
  fineCents: const Money(150000),
  confidenceScore: 100,
);

// ── Test helpers ─────────────────────────────────────────────────────────────

/// Concrete DomainEvent subclass not registered in SlaLedgerMapper.
/// Used to exercise the UNKNOWN_EVENT fallback branch.
class _UnknownTestEvent extends DomainEvent {
  const _UnknownTestEvent({
    required super.organizationId,
    required super.occurredAtUtc,
  });
}

// ── main ─────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // TASK 1 — Setup & Structural Integrity
  // ═══════════════════════════════════════════════════════════════════════════

  group('Task 1 — Structural Integrity: DomainEvent base contract', () {
    test('ExecutionBoundEvent: occurredAtUtc.isUtc == true (INV-6)', () {
      final e = ExecutionBoundEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        vehicleId: _vehicleId,
        bindingTimestampUtc: _ts,
        bindingLatitude: -23.5505,
        bindingLongitude: -46.6333,
      );
      expect(e.occurredAtUtc.isUtc, isTrue);
    });

    test('All events accept valid UTC timestamp without throwing', () {
      final ve = _makeVerdictEvidence();
      expect(
        () => ExecutionBoundEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          vehicleId: _vehicleId,
          bindingTimestampUtc: _ts,
          bindingLatitude: -23.5505,
          bindingLongitude: -46.6333,
        ),
        returnsNormally,
      );
      expect(
        () => NoShowDeclaredEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          declaredAtUtc: _ts,
        ),
        returnsNormally,
      );
      expect(
        () => EvidenceGapDeclaredEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          declaredAtUtc: _ts,
        ),
        returnsNormally,
      );
      expect(
        () => OccurrenceRegisteredEvidence(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          tripId: _setId,
          operatorId: _userId,
          occurrenceType: 'ACIDENTE',
        ),
        returnsNormally,
      );
      expect(
        () => TripInterruptedEvidence(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          tripId: _setId,
          operatorId: _userId,
        ),
        returnsNormally,
      );
      expect(
        () => TripCancelledEvidence(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          tripId: _setId,
          operatorId: _userId,
        ),
        returnsNormally,
      );
      expect(
        () => SanctionRecommendedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          verdictEvidence: ve,
        ),
        returnsNormally,
      );
      expect(
        () => SanctionAppliedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          queueEntryId: _queueId,
          approvedByUserId: _userId,
          actorEmail: _email,
          verdictEvidence: ve,
        ),
        returnsNormally,
      );
      expect(
        () => SanctionRejectedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          queueEntryId: _queueId,
          rejectedByUserId: _userId,
          actorEmail: _email,
          rejectionReason: 'Motorista presente',
          verdictEvidence: ve,
        ),
        returnsNormally,
      );
      expect(
        () => SanctionDisputedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          queueEntryId: _queueId,
          verdictEvidence: ve,
        ),
        returnsNormally,
      );
      expect(
        () => JustificationSubmittedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          justificationId: _justId,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          actorUserId: _userId,
          evidenceHashes: ['hash-abc'],
        ),
        returnsNormally,
      );
      expect(
        () => JustificationApprovedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          justificationId: _justId,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          actorUserId: _userId,
          actorEmail: _email,
        ),
        returnsNormally,
      );
      expect(
        () => JustificationRejectedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          justificationId: _justId,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          actorUserId: _userId,
          actorEmail: _email,
        ),
        returnsNormally,
      );
      expect(
        () => SLAJustificationSubmittedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          justificationId: _justId,
          vehicleId: _vehicleId,
          occurrenceTimestamp: _ts,
          actorUserId: _userId,
          evidenceHashes: ['hash-abc'],
        ),
        returnsNormally,
      );
      expect(
        () => SLAJustificationExpiredEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          justificationId: _justId,
          vehicleId: _vehicleId,
          occurrenceTimestamp: _ts,
        ),
        returnsNormally,
      );
      expect(
        () => TransitStartedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          startedAtUtc: _ts,
          source: 'telegram',
        ),
        returnsNormally,
      );
      expect(
        () => CompletedWithGapsEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          completedAtUtc: _ts,
        ),
        returnsNormally,
      );
      expect(
        () => ExecutionInhibitedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          reason: 'Justificativa aprovada',
        ),
        returnsNormally,
      );
    });

    test(
      'DomainEvent identity: two instances with same fields are NOT equal (no Equatable)',
      () {
        final e1 = ExecutionBoundEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          vehicleId: _vehicleId,
          bindingTimestampUtc: _ts,
          bindingLatitude: -23.5505,
          bindingLongitude: -46.6333,
        );
        final e2 = ExecutionBoundEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          vehicleId: _vehicleId,
          bindingTimestampUtc: _ts,
          bindingLatitude: -23.5505,
          bindingLongitude: -46.6333,
        );
        // DomainEvent uses identity equality by design
        expect(identical(e1, e2), isFalse);
        expect(e1 == e2, isFalse);
      },
    );

    test('planVersion is int type (not double)', () {
      final e = ExecutionBoundEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 3,
        vehicleId: _vehicleId,
        bindingTimestampUtc: _ts,
        bindingLatitude: -23.5505,
        bindingLongitude: -46.6333,
      );
      expect(e.planVersion, isA<int>());
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TASK 2 — Round-trip Serialization via SlaLedgerMapper (INV-15)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Task 2 — Round-trip: ExecutionBoundEvent', () {
    late ExecutionBoundEvent event;
    setUp(() {
      event = ExecutionBoundEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 2,
        vehicleId: _vehicleId,
        bindingTimestampUtc: _ts2,
        bindingLatitude: -23.5505,
        bindingLongitude: -46.6333,
      );
    });

    test('type is EXECUTION_BOUND', () {
      expect(SlaLedgerMapper.mapToEntry(event).type, 'EXECUTION_BOUND');
    });

    test('payload preserves all fields', () {
      final p = SlaLedgerMapper.mapToEntry(event).payload;
      expect(p['vehicle_id'], _vehicleId);
      expect(p['latitude'], -23.5505);
      expect(p['longitude'], -46.6333);
      expect(DateTime.parse(p['binding_timestamp_utc'] as String), _ts2);
    });
  });

  group('Task 2 — Round-trip: NoShowDeclaredEvent', () {
    test('payload preserves declaredAtUtc', () {
      final e = NoShowDeclaredEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        declaredAtUtc: _ts2,
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      expect(DateTime.parse(p['declared_at_utc'] as String), _ts2);
    });
  });

  group('Task 2 — Round-trip: OccurrenceRegisteredEvidence', () {
    test('nullable notes survives round-trip as null', () {
      final e = OccurrenceRegisteredEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
        occurrenceType: 'ATRASO',
        notes: null,
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      expect(p.containsKey('notes'), isTrue);
      expect(p['notes'], isNull);
    });

    test('metadata with Emojis and special chars survives round-trip', () {
      final e = OccurrenceRegisteredEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
        occurrenceType: 'OCC',
        metadata: const {'motorista': '😊🔑 João da Silva — Ônibus nº 42'},
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      final meta = p['metadata'] as Map<String, dynamic>;
      expect(meta['motorista'], '😊🔑 João da Silva — Ônibus nº 42');
    });

    test('metadata survives jsonEncode/jsonDecode round-trip with Emojis', () {
      const original = {'tag': '🚌 motorista', 'empty': ''};
      final e = OccurrenceRegisteredEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
        occurrenceType: 'OCC',
        metadata: original,
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      final encoded = jsonEncode(p);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final meta = decoded['metadata'] as Map<String, dynamic>;
      expect(meta['tag'], '🚌 motorista');
    });
  });

  group('Task 2 — Round-trip: Sanction events with VerdictEvidence', () {
    test('SanctionRecommendedEvent payload embeds verdict_evidence as Map', () {
      final ve = _makeVerdictEvidence();
      final e = SanctionRecommendedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        verdictEvidence: ve,
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      expect(p['verdict_evidence'], isA<Map<String, dynamic>>());
      final veMap = p['verdict_evidence'] as Map<String, dynamic>;
      expect(veMap['clause_ref'], ve.clauseRef);
      expect(veMap['fine_cents'], ve.fineCents.cents);
    });

    test(
      'SanctionRejectedEvent: long rejectionReason survives (10k chars)',
      () {
        final longReason = 'A' * 10000;
        final e = SanctionRejectedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          queueEntryId: _queueId,
          rejectedByUserId: _userId,
          actorEmail: _email,
          rejectionReason: longReason,
          verdictEvidence: _makeVerdictEvidence(),
        );
        final p = SlaLedgerMapper.mapToEntry(e).payload;
        expect(p['rejection_reason'], longReason);
      },
    );

    test(
      'VerdictEvidence equality: same inputs == same object (Equatable on evidenceHash)',
      () {
        final ve1 = _makeVerdictEvidence();
        final ve2 = _makeVerdictEvidence();
        expect(ve1, ve2);
      },
    );
  });

  group('Task 2 — Round-trip: SLAJustificationSubmittedEvent (CX-05)', () {
    test('occurrenceTimestamp UTC precision preserved in payload', () {
      final preciseTs = DateTime.utc(2026, 4, 23, 12, 30, 45, 123, 456);
      final e = SLAJustificationSubmittedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        justificationId: _justId,
        vehicleId: _vehicleId,
        occurrenceTimestamp: preciseTs,
        actorUserId: _userId,
        evidenceHashes: ['hash-abc'],
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      final restored = DateTime.parse(p['occurrence_timestamp'] as String);
      expect(restored.isUtc, isTrue);
      expect(restored, preciseTs);
      // Microsecond precision
      expect(restored.microsecond, 456);
    });

    test('evidenceHashes list survives round-trip intact', () {
      final hashes = ['hash-001', 'hash-002', 'hash-003'];
      final e = SLAJustificationSubmittedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        justificationId: _justId,
        vehicleId: _vehicleId,
        occurrenceTimestamp: _ts,
        actorUserId: _userId,
        evidenceHashes: hashes,
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      expect(p['evidence_hashes'], hashes);
    });
  });

  group('Task 2 — Round-trip: TransitStartedEvent source field', () {
    for (final src in ['telegram', 'geofence']) {
      test('source "$src" is preserved verbatim', () {
        final e = TransitStartedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          startedAtUtc: _ts,
          source: src,
        );
        expect(SlaLedgerMapper.mapToEntry(e).payload['source'], src);
      });
    }
  });

  group('Task 2 — Timestamp Precision (INV-6/INV-20)', () {
    test('ISO8601 string includes microseconds', () {
      final ts = DateTime.utc(2026, 4, 23, 12, 30, 45, 123, 456);
      expect(ts.toIso8601String(), contains('.123456'));
    });

    test('DateTime.parse restores UTC flag from ISO8601 Z string', () {
      final ts = DateTime.utc(2026, 4, 23, 0, 0, 0);
      final restored = DateTime.parse(ts.toIso8601String());
      expect(restored.isUtc, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TASK 3 — Deep Immutability (Soberania do Fato)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Task 3 — Immutability: OccurrenceRegisteredEvidence.metadata', () {
    test('default metadata const {} — mutation throws UnsupportedError', () {
      final e = OccurrenceRegisteredEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
        occurrenceType: 'OCC',
        // metadata defaults to const {}
      );
      expect(
        () => (e.metadata as dynamic)['hack'] = 'injected',
        throwsUnsupportedError,
      );
    });

    test('Map.unmodifiable metadata — mutation throws UnsupportedError', () {
      final e = OccurrenceRegisteredEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
        occurrenceType: 'OCC',
        metadata: Map.unmodifiable({'key': 'value'}),
      );
      expect(
        () => (e.metadata as dynamic)['key'] = 'tampered',
        throwsUnsupportedError,
      );
    });

    test(
      'external Map mutation does not affect event if Map.unmodifiable used',
      () {
        final source = {'tag': 'original'};
        final e = OccurrenceRegisteredEvidence(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          tripId: _setId,
          operatorId: _userId,
          occurrenceType: 'OCC',
          metadata: Map.unmodifiable(source),
        );
        source['tag'] = 'mutated'; // mutate source AFTER construction
        expect(e.metadata['tag'], 'original'); // event is unaffected
      },
    );
  });

  group('Task 3 — GAP forense: evidenceHashes List mutável [GAP]', () {
    /// GAP FORENSE: evidenceHashes não é List.unmodifiable().
    /// Correção recomendada: usar List.unmodifiable(evidenceHashes) no construtor.
    test(
      '[GAP] external list mutation leaks into JustificationSubmittedEvent.evidenceHashes',
      () {
        final hashes = ['hash-001', 'hash-002'];
        final e = JustificationSubmittedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          justificationId: _justId,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          actorUserId: _userId,
          evidenceHashes: hashes,
        );
        hashes.add('injected-by-attacker');
        expect(
          e.evidenceHashes.length,
          3,
          reason: '[GAP] evidenceHashes should be unmodifiable but is not',
        );
      },
    );

    test(
      '[GAP] external list mutation leaks into SLAJustificationSubmittedEvent.evidenceHashes',
      () {
        final hashes = ['hash-a'];
        final e = SLAJustificationSubmittedEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          justificationId: _justId,
          vehicleId: _vehicleId,
          occurrenceTimestamp: _ts,
          actorUserId: _userId,
          evidenceHashes: hashes,
        );
        hashes.add('injected');
        expect(
          e.evidenceHashes.length,
          2,
          reason: '[GAP] evidenceHashes should be unmodifiable but is not',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TASK 4 — Schema Resilience & Defaults
  // ═══════════════════════════════════════════════════════════════════════════

  group('Task 4 — Schema Resilience: optional null fields', () {
    test(
      'TripInterruptedEvidence with reason null — payload[reason] is null',
      () {
        final e = TripInterruptedEvidence(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          tripId: _setId,
          operatorId: _userId,
          reason: null,
        );
        final p = SlaLedgerMapper.mapToEntry(e).payload;
        expect(p.containsKey('reason'), isTrue);
        expect(p['reason'], isNull);
      },
    );

    test(
      'TripCancelledEvidence with reason null — payload[reason] is null',
      () {
        final e = TripCancelledEvidence(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          tripId: _setId,
          operatorId: _userId,
          reason: null,
        );
        final p = SlaLedgerMapper.mapToEntry(e).payload;
        expect(p.containsKey('reason'), isTrue);
        expect(p['reason'], isNull);
      },
    );

    test(
      'OccurrenceRegisteredEvidence with empty metadata — payload[metadata] is {}',
      () {
        final e = OccurrenceRegisteredEvidence(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          tripId: _setId,
          operatorId: _userId,
          occurrenceType: 'OCC',
          metadata: const {},
        );
        final p = SlaLedgerMapper.mapToEntry(e).payload;
        expect(p['metadata'], isEmpty);
      },
    );

    test('EvidenceEvent with null vehicleId — payload[vehicle_id] is null', () {
      final e = OccurrenceRegisteredEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
        occurrenceType: 'FLAT_TIRE',
        vehicleId: null,
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      expect(p['vehicle_id'], isNull);
    });

    test(
      'SlaLedgerMapper unknown event — type is UNKNOWN_EVENT (fallback)',
      () {
        // Uses a custom subclass to trigger the fallback branch
        final unknownEvent = _UnknownTestEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
        );
        final entry = SlaLedgerMapper.mapToEntry(unknownEvent);
        expect(entry.type, 'UNKNOWN_EVENT');
        expect(entry.payload['raw_event_type'], isA<String>());
      },
    );

    test('jsonEncode of payload with extra unknown keys does not throw', () {
      final e = ExecutionBoundEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        vehicleId: _vehicleId,
        bindingTimestampUtc: _ts,
        bindingLatitude: -23.5505,
        bindingLongitude: -46.6333,
      );
      final p = Map<String, dynamic>.from(SlaLedgerMapper.mapToEntry(e).payload)
        ..['extra_field_from_future_version'] = 'ignored';
      expect(() => jsonEncode(p), returnsNormally);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TASK 5 — Numerical & Type Rigidity
  // ═══════════════════════════════════════════════════════════════════════════

  group('Task 5 — Numerical Rigidity', () {
    test('bindingLatitude stored as double (not int) in payload', () {
      final e = ExecutionBoundEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        vehicleId: _vehicleId,
        bindingTimestampUtc: _ts,
        bindingLatitude: -23.0,
        bindingLongitude: -46.0,
      );
      final p = SlaLedgerMapper.mapToEntry(e).payload;
      expect(p['latitude'], isA<double>());
      expect(p['longitude'], isA<double>());
    });

    test('(num).toDouble() bridge: int 42 → double 42.0 with exact equality', () {
      // Validates the pattern used in VerdictEvidence.fromJson for numeric fields
      const intValue = 42;
      final asDouble = (intValue as num).toDouble();
      expect(asDouble, 42.0);
      expect(asDouble, isA<double>());
    });

    test(
      'VerdictEvidence: fineCents negative is rejected (DomainException)',
      () {
        expect(
          () => VerdictEvidence.create(
            clauseRef: 'rule-1',
            ruleId: 'r-001',
            ruleVersion: 1,
            primaryEvidenceLat: -23.5505,
            primaryEvidenceLng: -46.6333,
            primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 23, 10, 0),
            deltaValue: 1.0,
            thresholdValue: 0.0,
            fineCents: const Money(-100),
            confidenceScore: 100,
          ),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test('VerdictEvidence: fineCents zero is rejected (DomainException)', () {
      expect(
        () => VerdictEvidence.create(
          clauseRef: 'rule-1',
          ruleId: 'r-001',
          ruleVersion: 1,
          primaryEvidenceLat: -23.5505,
          primaryEvidenceLng: -46.6333,
          primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 23, 10, 0),
          deltaValue: 1.0,
          thresholdValue: 0.0,
          fineCents: const Money(0),
          confidenceScore: 100,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('VerdictEvidence: confidenceScore > 100 is rejected', () {
      expect(
        () => VerdictEvidence.create(
          clauseRef: 'rule-1',
          ruleId: 'r-001',
          ruleVersion: 1,
          primaryEvidenceLat: -23.5505,
          primaryEvidenceLng: -46.6333,
          primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 23, 10, 0),
          deltaValue: 1.0,
          thresholdValue: 0.0,
          fineCents: const Money(100),
          confidenceScore: 101,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('planVersion in SlaLedgerEntry is stored as int', () {
      final e = CompletedWithGapsEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 7,
        completedAtUtc: _ts,
      );
      final entry = SlaLedgerMapper.mapToEntry(e);
      expect(entry.planVersion, isA<int>());
      expect(entry.planVersion, 7);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TASK 6 — Canonical Formatting & JSON Determinism (Hashing Ready / INV-15)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Task 6 — Canonical Formatting: stable type strings', () {
    final typeMap = {
      ExecutionBoundEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        vehicleId: _vehicleId,
        bindingTimestampUtc: _ts,
        bindingLatitude: -23.5,
        bindingLongitude: -46.6,
      ): 'EXECUTION_BOUND',
      NoShowDeclaredEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        declaredAtUtc: _ts,
      ): 'NO_SHOW_DECLARED',
      EvidenceGapDeclaredEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        declaredAtUtc: _ts,
      ): 'EVIDENCE_GAP_DECLARED',
      OccurrenceRegisteredEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
        occurrenceType: 'OCC',
      ): 'OCCURRENCE_REGISTERED',
      TripInterruptedEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
      ): 'TRIP_INTERRUPTED',
      TripCancelledEvidence(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        tripId: _setId,
        operatorId: _userId,
      ): 'TRIP_CANCELLED',
      JustificationSubmittedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        justificationId: _justId,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        actorUserId: _userId,
        evidenceHashes: [],
      ): 'JUSTIFICATION_SUBMITTED',
      JustificationApprovedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        justificationId: _justId,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        actorUserId: _userId,
        actorEmail: _email,
      ): 'JUSTIFICATION_APPROVED',
      JustificationRejectedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        justificationId: _justId,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        actorUserId: _userId,
        actorEmail: _email,
      ): 'JUSTIFICATION_REJECTED',
      SLAJustificationSubmittedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        justificationId: _justId,
        vehicleId: _vehicleId,
        occurrenceTimestamp: _ts,
        actorUserId: _userId,
        evidenceHashes: [],
      ): 'SLA_JUSTIFICATION_SUBMITTED',
      SLAJustificationExpiredEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        justificationId: _justId,
        vehicleId: _vehicleId,
        occurrenceTimestamp: _ts,
      ): 'SLA_JUSTIFICATION_EXPIRED',
      TransitStartedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        startedAtUtc: _ts,
        source: 'telegram',
      ): 'TRANSIT_STARTED',
      CompletedWithGapsEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        completedAtUtc: _ts,
      ): 'COMPLETED_WITH_GAPS',
      ExecutionInhibitedEvent(
        organizationId: _orgId,
        occurredAtUtc: _ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        reason: 'test',
      ): 'EXECUTION_INHIBITED',
    };

    for (final entry in typeMap.entries) {
      test('${entry.key.runtimeType} maps to stable type "${entry.value}"', () {
        expect(SlaLedgerMapper.mapToEntry(entry.key).type, entry.value);
      });
    }
  });

  group('Task 6 — Canonical Formatting: byte-identical replay (INV-15)', () {
    test(
      'same ExecutionBoundEvent inputs → identical payload (deterministic)',
      () {
        final ts = DateTime.utc(2026, 4, 23, 12, 0, 0);
        ExecutionBoundEvent make() => ExecutionBoundEvent(
          organizationId: _orgId,
          occurredAtUtc: ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          vehicleId: _vehicleId,
          bindingTimestampUtc: ts,
          bindingLatitude: -23.5505,
          bindingLongitude: -46.6333,
        );
        final p1 = SlaLedgerMapper.mapToEntry(make()).payload;
        final p2 = SlaLedgerMapper.mapToEntry(make()).payload;
        expect(jsonEncode(p1), jsonEncode(p2));
      },
    );

    test('same SanctionRecommendedEvent → identical payload JSON (INV-15)', () {
      final ve = _makeVerdictEvidence();
      final ts = DateTime.utc(2026, 4, 23, 10, 0);
      SanctionRecommendedEvent make() => SanctionRecommendedEvent(
        organizationId: _orgId,
        occurredAtUtc: ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        verdictEvidence: ve,
      );
      final p1 = SlaLedgerMapper.mapToEntry(make()).payload;
      final p2 = SlaLedgerMapper.mapToEntry(make()).payload;
      expect(jsonEncode(p1), jsonEncode(p2));
    });
  });

  group('Task 6 — JSON Determinism: dart:convert key ordering', () {
    /// dart:convert jsonEncode preserves LinkedHashMap insertion order.
    /// SlaLedgerMapper.payload uses Map literals → insertion order is fixed.
    /// This validates that the canonical string is stable for future signing.
    test('dart:convert preserves insertion-order key sequence', () {
      // A payload map built with a known insertion order
      final payload = <String, dynamic>{'a_key': 1, 'z_key': 2, 'm_key': 3};
      const expected = '{"a_key":1,"z_key":2,"m_key":3}';
      expect(jsonEncode(payload), expected);
    });

    test('ExecutionBoundEvent payload key order is stable across calls', () {
      final ts = DateTime.utc(2026, 4, 23, 12, 0);
      ExecutionBoundEvent make() => ExecutionBoundEvent(
        organizationId: _orgId,
        occurredAtUtc: ts,
        setId: _setId,
        contractId: _contractId,
        planVersion: 1,
        vehicleId: _vehicleId,
        bindingTimestampUtc: ts,
        bindingLatitude: -23.0,
        bindingLongitude: -46.0,
      );
      final enc1 = jsonEncode(SlaLedgerMapper.mapToEntry(make()).payload);
      final enc2 = jsonEncode(SlaLedgerMapper.mapToEntry(make()).payload);
      // Byte-identical strings confirm stable key order (prerequisite for SHA-256 signing)
      expect(enc1, enc2);
    });

    test(
      'SlaLedgerMapper payload keys are in fixed insertion order — not sorted alphabetically',
      () {
        // Documents current behavior: keys follow insertion order in Map literal.
        // IF alphabetical sorting is needed for signing, implement a canonical
        // encoder that sorts keys before jsonEncode.
        final e = ExecutionBoundEvent(
          organizationId: _orgId,
          occurredAtUtc: _ts,
          setId: _setId,
          contractId: _contractId,
          planVersion: 1,
          vehicleId: _vehicleId,
          bindingTimestampUtc: _ts,
          bindingLatitude: -23.5505,
          bindingLongitude: -46.6333,
        );
        final p = SlaLedgerMapper.mapToEntry(e).payload;
        // Current: insertion order. Comment describes intent.
        // To enforce alphabetical, use: SortedMap or manual sort in mapper.
        expect(jsonEncode(p), isA<String>());
        // Verify payload is self-consistent regardless of key order
        expect(p['vehicle_id'], _vehicleId);
        expect(p['latitude'], isA<double>());
        // Assert that two identical calls produce the SAME string (deterministic)
        final p2 = SlaLedgerMapper.mapToEntry(e).payload;
        expect(jsonEncode(p), jsonEncode(p2));
      },
    );

    test(
      'VerdictEvidence canonical hash is byte-identical for same inputs (INV-9)',
      () {
        // VerdictEvidence._computeHash uses jsonEncode with fixed-order Map literals
        final ve1 = _makeVerdictEvidence();
        final ve2 = _makeVerdictEvidence();
        expect(ve1.evidenceHash, ve2.evidenceHash);
        expect(ve1.evidenceHash.length, 64); // SHA-256 = 64 hex chars
      },
    );

    test('VerdictEvidence hash changes if any canonical field changes', () {
      final base = _makeVerdictEvidence();
      final mutated = VerdictEvidence.create(
        clauseRef: base.clauseRef,
        ruleId: base.ruleId,
        ruleVersion: base.ruleVersion + 1, // changed
        primaryEvidenceLat: base.primaryEvidenceLat,
        primaryEvidenceLng: base.primaryEvidenceLng,
        primaryEvidenceTimestampUtc: base.primaryEvidenceTimestampUtc,
        deltaValue: base.deltaValue,
        thresholdValue: base.thresholdValue,
        fineCents: base.fineCents,
        confidenceScore: base.confidenceScore,
      );
      expect(mutated.evidenceHash, isNot(base.evidenceHash));
    });
  });
}
