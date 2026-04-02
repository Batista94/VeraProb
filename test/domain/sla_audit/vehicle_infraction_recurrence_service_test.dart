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
  }) async {
    return _data
        .where((e) =>
            e.organizationId == organizationId &&
            e.id != excludeQueueEntryId)
        .toList();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

VerdictEvidence _evidence(String clauseRef) => VerdictEvidence.create(
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

SanctionReviewQueueEntry _entry({
  required String id,
  required String clauseRef,
  DateTime? createdAt,
}) =>
    SanctionReviewQueueEntry(
      id: id,
      organizationId: 'org-1',
      ledgerEntryId: 'ledger-$id',
      setId: 'set-1',
      contractId: 'contract-1',
      verdictEvidence: _evidence(clauseRef),
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
      final prior1 = _entry(
        id: 'prior-1',
        clauseRef: 'VEL-001',
        createdAt: DateTime.utc(2026, 4, 2, 8, 0),
      );
      final prior2 = _entry(
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
      final current = _entry(id: 'curr-1', clauseRef: 'VEL-001');
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
      final prior = _entry(
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
  });
}
