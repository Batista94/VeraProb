import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_evidence.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_submission_token.dart';

void main() {
  // ── Fixtures ──────────────────────────────────────────────────────────────
  final now = DateTime.utc(2026, 5, 2, 8, 0);
  final future = now.add(const Duration(hours: 24));

  ContractorJustification makeJustification({
    JustificationStatus status = JustificationStatus.pending,
    String? reviewedByUserId,
    DateTime? reviewedAtUtc,
  }) {
    return ContractorJustification(
      id: 'just-001',
      organizationId: 'org-abc',
      contractId: 'CTR-100',
      setId: 'SET-XYZ',
      submittedByToken: null,
      category: JustificationCategory.mechanical,
      description: 'Vehicle broke down due to engine failure on route.',
      status: status,
      reviewedByUserId: reviewedByUserId,
      reviewedAtUtc: reviewedAtUtc,
      createdAtUtc: now,
    );
  }

  // ── JustificationCategory ─────────────────────────────────────────────────
  group('JustificationCategory', () {
    test('dbValue returns lowercase snake_case string', () {
      expect(JustificationCategory.mechanical.dbValue, 'MECHANICAL');
      expect(JustificationCategory.forceMajeure.dbValue, 'FORCE_MAJEURE');
      expect(JustificationCategory.traffic.dbValue, 'TRAFFIC');
      expect(JustificationCategory.routeDeviation.dbValue, 'ROUTE_DEVIATION');
      expect(JustificationCategory.communication.dbValue, 'COMMUNICATION');
      expect(JustificationCategory.other.dbValue, 'OTHER');
    });

    test('fromDb round-trips all values', () {
      for (final cat in JustificationCategory.values) {
        expect(JustificationCategory.fromDb(cat.dbValue), cat);
      }
    });

    test('fromDb throws on unknown value', () {
      expect(
        () => JustificationCategory.fromDb('UNKNOWN_VALUE'),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  // ── JustificationStatus ───────────────────────────────────────────────────
  group('JustificationStatus', () {
    test('dbValue returns uppercase string', () {
      expect(JustificationStatus.pending.dbValue, 'PENDING');
      expect(JustificationStatus.approved.dbValue, 'APPROVED');
      expect(JustificationStatus.rejected.dbValue, 'REJECTED');
    });

    test('fromDb round-trips all values', () {
      for (final s in JustificationStatus.values) {
        expect(JustificationStatus.fromDb(s.dbValue), s);
      }
    });

    test('fromDb throws on unknown value', () {
      expect(
        () => JustificationStatus.fromDb('INVALID'),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  // ── JustificationEvidence ─────────────────────────────────────────────────
  group('JustificationEvidence', () {
    test('equality is value-based (all fields)', () {
      final e1 = JustificationEvidence(
        id: 'ev-1',
        justificationId: 'just-001',
        organizationId: 'org-abc',
        fileName: 'photo.jpg',
        contentHash: 'a' * 64,
        storagePath: 'org-abc/just-001/photo.jpg',
        uploadedAtUtc: now,
      );
      final e2 = JustificationEvidence(
        id: 'ev-1',
        justificationId: 'just-001',
        organizationId: 'org-abc',
        fileName: 'photo.jpg',
        contentHash: 'a' * 64,
        storagePath: 'org-abc/just-001/photo.jpg',
        uploadedAtUtc: now,
      );
      expect(e1, e2);
    });

    test('different id means not equal', () {
      final e1 = JustificationEvidence(
        id: 'ev-1',
        justificationId: 'just-001',
        organizationId: 'org-abc',
        fileName: 'photo.jpg',
        contentHash: 'a' * 64,
        storagePath: 'org-abc/just-001/photo.jpg',
        uploadedAtUtc: now,
      );
      final e2 = JustificationEvidence(
        id: 'ev-2',
        justificationId: 'just-001',
        organizationId: 'org-abc',
        fileName: 'photo.jpg',
        contentHash: 'a' * 64,
        storagePath: 'org-abc/just-001/photo.jpg',
        uploadedAtUtc: now,
      );
      expect(e1, isNot(e2));
    });
  });

  // ── JustificationSubmissionToken ──────────────────────────────────────────
  group('JustificationSubmissionToken', () {
    test('isActive when not used and not expired', () {
      final token = JustificationSubmissionToken(
        id: 'tok-1',
        organizationId: 'org-abc',
        contractId: 'CTR-100',
        setId: 'SET-XYZ',
        justificationId: null,
        token: 'test-token',
        createdByUserId: 'user-1',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 24)),
        usedAtUtc: null,
        createdAtUtc: DateTime.now().toUtc(),
      );
      expect(token.isActive, isTrue);
    });

    test('isActive false when already used', () {
      final token = JustificationSubmissionToken(
        id: 'tok-2',
        organizationId: 'org-abc',
        contractId: 'CTR-100',
        setId: 'SET-XYZ',
        justificationId: 'just-001',
        token: 'test-token',
        createdByUserId: 'user-1',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 24)),
        usedAtUtc: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        createdAtUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      expect(token.isActive, isFalse);
    });

    test('isActive false when expired', () {
      final token = JustificationSubmissionToken(
        id: 'tok-3',
        organizationId: 'org-abc',
        contractId: 'CTR-100',
        setId: 'SET-XYZ',
        justificationId: null,
        token: 'test-token',
        createdByUserId: 'user-1',
        expiresAtUtc: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        usedAtUtc: null,
        createdAtUtc: DateTime.now().toUtc().subtract(
          const Duration(hours: 25),
        ),
      );
      expect(token.isActive, isFalse);
    });
  });

  // ── ContractorJustification ───────────────────────────────────────────────
  group('ContractorJustification', () {
    test('creates with pending status', () {
      final j = makeJustification();
      expect(j.status, JustificationStatus.pending);
      expect(j.isPending, isTrue);
      expect(j.isApproved, isFalse);
      expect(j.isRejected, isFalse);
    });

    test('copyWith transitions to approved', () {
      final j = makeJustification();
      final reviewed = j.copyWith(
        status: JustificationStatus.approved,
        reviewedByUserId: 'user-admin',
        reviewedAtUtc: future,
      );
      expect(reviewed.isApproved, isTrue);
      expect(reviewed.reviewedByUserId, 'user-admin');
      expect(reviewed.reviewedAtUtc, future);
    });

    test('copyWith transitions to rejected', () {
      final j = makeJustification();
      final rejected = j.copyWith(
        status: JustificationStatus.rejected,
        reviewedByUserId: 'user-admin',
        reviewedAtUtc: future,
      );
      expect(rejected.isRejected, isTrue);
    });

    test('copyWith does not mutate original', () {
      final j = makeJustification();
      j.copyWith(status: JustificationStatus.approved);
      expect(j.isPending, isTrue);
    });

    test('identity-based equality — same id, different status are equal', () {
      final j1 = makeJustification(status: JustificationStatus.pending);
      final j2 = makeJustification(status: JustificationStatus.approved);
      expect(j1, j2); // props = [id]
    });

    test('different ids are not equal', () {
      final j1 = makeJustification();
      final j2 = ContractorJustification(
        id: 'just-002',
        organizationId: 'org-abc',
        contractId: 'CTR-100',
        setId: 'SET-XYZ',
        submittedByToken: null,
        category: JustificationCategory.traffic,
        description: 'Heavy traffic on highway blocked the route entirely.',
        status: JustificationStatus.pending,
        reviewedByUserId: null,
        reviewedAtUtc: null,
        createdAtUtc: now,
      );
      expect(j1, isNot(j2));
    });

    test('immutable fields are preserved across copyWith', () {
      final j = makeJustification();
      final updated = j.copyWith(
        status: JustificationStatus.approved,
        reviewedByUserId: 'u-1',
      );
      expect(updated.id, j.id);
      expect(updated.organizationId, j.organizationId);
      expect(updated.contractId, j.contractId);
      expect(updated.setId, j.setId);
      expect(updated.category, j.category);
      expect(updated.description, j.description);
      expect(updated.createdAtUtc, j.createdAtUtc);
    });
  });
}
