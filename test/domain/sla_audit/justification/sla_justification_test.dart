import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  final occurrenceTimestamp = DateTime.utc(2026, 4, 14, 10, 30);
  final createdAt = DateTime.utc(2026, 4, 14, 11, 0);

  SLAJustification buildJustification({
    String id = 'just-1',
    JustificationStatus status = JustificationStatus.pending,
  }) {
    return SLAJustification(
      id: id,
      organizationId: 'org-1',
      vehicleId: 'vehicle-42',
      occurrenceTimestamp: occurrenceTimestamp,
      category: SLAJustificationCategory.pneuFurado,
      description: 'Pneu furado na BR-116 km 230',
      evidenceUrls: ['https://storage.supabase.co/evidence/photo1.jpg'],
      evidenceHashes: [
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      ],
      status: status,
      createdAt: createdAt,
      reviewerId: null,
      resolutionNotes: null,
    );
  }

  group('SLAJustification — Entity Construction', () {
    test('constructs with all required fields', () {
      final j = buildJustification();

      expect(j.id, 'just-1');
      expect(j.organizationId, 'org-1');
      expect(j.vehicleId, 'vehicle-42');
      expect(j.occurrenceTimestamp, occurrenceTimestamp);
      expect(j.category, SLAJustificationCategory.pneuFurado);
      expect(j.description, 'Pneu furado na BR-116 km 230');
      expect(j.evidenceUrls, hasLength(1));
      expect(j.evidenceHashes, hasLength(1));
      expect(j.status, JustificationStatus.pending);
      expect(j.createdAt, createdAt);
      expect(j.reviewerId, isNull);
      expect(j.resolutionNotes, isNull);
    });

    test('status helpers return correct booleans', () {
      expect(
        buildJustification(status: JustificationStatus.pending).isPending,
        isTrue,
      );
      expect(
        buildJustification(status: JustificationStatus.approved).isApproved,
        isTrue,
      );
      expect(
        buildJustification(status: JustificationStatus.rejected).isRejected,
        isTrue,
      );
      expect(
        buildJustification(status: JustificationStatus.expired).isExpired,
        isTrue,
      );
    });
  });

  group('SLAJustification — Forensic Immutability', () {
    test(
      'copyWith preserves vehicleId and occurrenceTimestamp (forensic anchor)',
      () {
        final original = buildJustification();
        final updated = original.copyWith(
          status: JustificationStatus.approved,
          reviewerId: 'reviewer-1',
          resolutionNotes: 'Evidência válida',
        );

        // Forensic anchor MUST be immutable
        expect(updated.vehicleId, original.vehicleId);
        expect(updated.occurrenceTimestamp, original.occurrenceTimestamp);

        // Review fields changed
        expect(updated.status, JustificationStatus.approved);
        expect(updated.reviewerId, 'reviewer-1');
        expect(updated.resolutionNotes, 'Evidência válida');

        // Other immutable fields preserved
        expect(updated.category, original.category);
        expect(updated.description, original.description);
        expect(updated.evidenceUrls, original.evidenceUrls);
        expect(updated.evidenceHashes, original.evidenceHashes);
        expect(updated.createdAt, original.createdAt);
      },
    );

    test('copyWith does NOT expose vehicleId or occurrenceTimestamp', () {
      // Compile-time guarantee: copyWith has no vehicleId/occurrenceTimestamp params.
      // This test documents the design intent — if someone adds those params,
      // this test description should remind them WHY they were excluded.
      final j = buildJustification();
      final copy = j.copyWith(status: JustificationStatus.rejected);

      expect(copy.vehicleId, j.vehicleId);
      expect(copy.occurrenceTimestamp, j.occurrenceTimestamp);
    });
  });

  group('SLAJustification — Identity Equality', () {
    test('two instances with same id are equal regardless of status', () {
      final pending = buildJustification(
        id: 'same-id',
        status: JustificationStatus.pending,
      );
      final approved = buildJustification(
        id: 'same-id',
        status: JustificationStatus.approved,
      );

      expect(pending, equals(approved));
    });

    test('two instances with different ids are not equal', () {
      final a = buildJustification(id: 'id-a');
      final b = buildJustification(id: 'id-b');

      expect(a, isNot(equals(b)));
    });
  });

  group('SLAJustificationCategory — DB Mapping', () {
    test('all categories round-trip through DB values', () {
      for (final category in SLAJustificationCategory.values) {
        final dbValue = category.dbValue;
        final restored = SLAJustificationCategory.fromDb(dbValue);
        expect(restored, category);
      }
    });

    test('unknown DB value throws ArgumentError', () {
      expect(
        () => SLAJustificationCategory.fromDb('INVALID'),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  group('JustificationStatus — EXPIRED', () {
    test('expired round-trips through DB value', () {
      final dbValue = JustificationStatus.expired.dbValue;
      expect(dbValue, 'EXPIRED');

      final restored = JustificationStatus.fromDb(dbValue);
      expect(restored, JustificationStatus.expired);
    });

    test('all statuses round-trip through DB values', () {
      for (final status in JustificationStatus.values) {
        final dbValue = status.dbValue;
        final restored = JustificationStatus.fromDb(dbValue);
        expect(restored, status);
      }
    });
  });
}
