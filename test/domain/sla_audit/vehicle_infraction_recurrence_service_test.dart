import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_repository.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_service.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/money.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class _FakeRepository implements VehicleInfractionRecurrenceRepository {
  final List<SanctionReviewQueueEntry> _data;
  _FakeRepository(this._data);

  @override
  Future<List<SanctionReviewQueueEntry>> findByPlateInMonth({
    required String organizationId,
    required String vehiclePlate,
    required DateTime referenceUtc,
    required String excludeQueueEntryId,
    required DateTime beforeUtc,
  }) async {
    return _data
        .where(
          (e) =>
              e.organizationId == organizationId &&
              e.id != excludeQueueEntryId &&
              e.createdAtUtc.isBefore(beforeUtc),
        )
        .toList();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

VerdictEvidence evidence(String clauseRef) => VerdictEvidence.create(
  clauseRef: clauseRef,
  ruleId: 'rule-1',
  ruleVersion: 1,
  primaryEvidenceLat: 0,
  primaryEvidenceLng: 0,
  primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 1, 8, 0),
  deltaValue: 10.0,
  thresholdValue: 5.0,
  fineCents: const Money(50000),
  confidenceScore: 90,
);

SanctionReviewQueueEntry entry({
  required String id,
  required String clauseRef,
  DateTime? createdAt,
}) => SanctionReviewQueueEntry(
  id: id,
  organizationId: 'org-1',
  ledgerEntryId: 'ledger-$id',
  setId: 'set-1',
  contractId: 'contract-1',
  verdictEvidence: evidence(clauseRef),
  status: SanctionReviewStatus.pending,
  createdAtUtc: createdAt ?? DateTime.utc(2026, 4, 1, 9, 0),
);

void main() {
  final refUtc = DateTime.utc(2026, 4, 15, 12, 0);

  group('VehicleInfractionRecurrenceService', () {
    test('returns null when vehiclePlate is null', () async {
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([]),
      );
      final result = await svc.computeRecurrence(
        organizationId: 'org-1',
        vehiclePlate: null,
        referenceUtc: refUtc,
        currentQueueEntryId: 'curr-1',
      );
      expect(result, isNull);
    });

    test('returns null when vehiclePlate is empty', () async {
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([]),
      );
      final result = await svc.computeRecurrence(
        organizationId: 'org-1',
        vehiclePlate: '',
        referenceUtc: refUtc,
        currentQueueEntryId: 'curr-1',
      );
      expect(result, isNull);
    });

    test('count=1 when no prior infractions exist', () async {
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([]),
      );
      final result = await svc.computeRecurrence(
        organizationId: 'org-1',
        vehiclePlate: 'ABC-1234',
        referenceUtc: refUtc,
        currentQueueEntryId: 'curr-1',
      );
      expect(result, isNotNull);
      expect(result!.infractionNumberThisMonth, 1);
      expect(result.priorInfractions, isEmpty);
    });

    test('count=N when N-1 priors exist', () async {
      final prior1 = entry(
        id: 'prior-1',
        clauseRef: 'VEL-001',
        createdAt: DateTime.utc(2026, 4, 2, 8, 0),
      );
      final prior2 = entry(
        id: 'prior-2',
        clauseRef: 'ATR-002',
        createdAt: DateTime.utc(2026, 4, 8, 10, 0),
      );
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([prior1, prior2]),
      );
      final result = await svc.computeRecurrence(
        organizationId: 'org-1',
        vehiclePlate: 'ABC-1234',
        referenceUtc: refUtc,
        currentQueueEntryId: 'curr-1',
      );
      expect(result!.infractionNumberThisMonth, 3);
      expect(result.priorInfractions.length, 2);
    });

    test('excludes current entry from priors', () async {
      final current = entry(id: 'curr-1', clauseRef: 'VEL-001');
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([current]),
      );
      final result = await svc.computeRecurrence(
        organizationId: 'org-1',
        vehiclePlate: 'ABC-1234',
        referenceUtc: refUtc,
        currentQueueEntryId: 'curr-1',
      );
      expect(result!.infractionNumberThisMonth, 1);
      expect(result.priorInfractions, isEmpty);
    });

    test('prior dots carry correct clauseRef and UTC timestamp', () async {
      final prior = entry(
        id: 'prior-1',
        clauseRef: 'VEL-001',
        createdAt: DateTime.utc(2026, 4, 3, 7, 30),
      );
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([prior]),
      );
      final result = await svc.computeRecurrence(
        organizationId: 'org-1',
        vehiclePlate: 'ABC-1234',
        referenceUtc: refUtc,
        currentQueueEntryId: 'curr-1',
      );
      final dot = result!.priorInfractions.first;
      expect(dot.clauseRef, 'VEL-001');
      expect(dot.occurredAtUtc, DateTime.utc(2026, 4, 3, 7, 30));
      expect(dot.occurredAtUtc.isUtc, isTrue);
    });

    test('asserts referenceUtc is UTC', () {
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([]),
      );
      expect(
        () => svc.computeRecurrence(
          organizationId: 'org-1',
          vehiclePlate: 'ABC-1234',
          referenceUtc: DateTime(2026, 4, 15, 12, 0), // local, not UTC
          currentQueueEntryId: 'curr-1',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('vehiclePlate propagated to report', () async {
      final svc = VehicleInfractionRecurrenceService(
        repository: _FakeRepository([]),
      );
      final result = await svc.computeRecurrence(
        organizationId: 'org-1',
        vehiclePlate: 'XYZ-9999',
        referenceUtc: refUtc,
        currentQueueEntryId: 'curr-1',
      );
      expect(result!.vehiclePlate, 'XYZ-9999');
    });

    // ── Sequence-number regression (Bug 2) ───────────────────────────────────
    // When a driver has N infractions in the same month, each card must show
    // its chronological rank (1ª, 2ª, … Nª), NOT the current total N.
    // Root cause: beforeUtc filter was missing — future cards counted as priors.
    group('infraction sequence number', () {
      DateTime t(int h) => DateTime.utc(2026, 4, 1, h, 0);

      late SanctionReviewQueueEntry card1, card2, card3, card4, card5;
      setUp(() {
        card1 = entry(id: 'e1', clauseRef: 'VEL-01', createdAt: t(10));
        card2 = entry(id: 'e2', clauseRef: 'VEL-01', createdAt: t(11));
        card3 = entry(id: 'e3', clauseRef: 'VEL-01', createdAt: t(12));
        card4 = entry(id: 'e4', clauseRef: 'VEL-01', createdAt: t(13));
        card5 = entry(id: 'e5', clauseRef: 'VEL-01', createdAt: t(14));
      });

      test('card 1 shows 1ª when 4 later cards exist', () async {
        final svc = VehicleInfractionRecurrenceService(
          repository: _FakeRepository([card1, card2, card3, card4, card5]),
        );
        final r = await svc.computeRecurrence(
          organizationId: 'org-1',
          vehiclePlate: 'ABC-1234',
          referenceUtc: card1.createdAtUtc,
          currentQueueEntryId: 'e1',
        );
        expect(
          r!.infractionNumberThisMonth,
          1,
          reason: 'no priors before first card — must show 1ª, not 5ª',
        );
        expect(r.priorInfractions, isEmpty);
      });

      test('card 3 shows 3ª', () async {
        final svc = VehicleInfractionRecurrenceService(
          repository: _FakeRepository([card1, card2, card3, card4, card5]),
        );
        final r = await svc.computeRecurrence(
          organizationId: 'org-1',
          vehiclePlate: 'ABC-1234',
          referenceUtc: card3.createdAtUtc,
          currentQueueEntryId: 'e3',
        );
        expect(
          r!.infractionNumberThisMonth,
          3,
          reason: 'two priors before card 3',
        );
        expect(r.priorInfractions, hasLength(2));
      });

      test('card 5 shows 5ª', () async {
        final svc = VehicleInfractionRecurrenceService(
          repository: _FakeRepository([card1, card2, card3, card4, card5]),
        );
        final r = await svc.computeRecurrence(
          organizationId: 'org-1',
          vehiclePlate: 'ABC-1234',
          referenceUtc: card5.createdAtUtc,
          currentQueueEntryId: 'e5',
        );
        expect(
          r!.infractionNumberThisMonth,
          5,
          reason: 'four priors before card 5',
        );
        expect(r.priorInfractions, hasLength(4));
      });
    });
  });
}
