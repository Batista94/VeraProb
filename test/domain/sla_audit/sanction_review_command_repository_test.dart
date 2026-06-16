import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_sanction_result.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';

/// Contract fake: tracks the terminal status of each entry so a second verdict
/// on an already-reviewed entry raises [IdempotencyProcessingException] — the
/// documented concurrency-loser semantics.
class _FakeReview implements SanctionReviewCommandRepository {
  final Map<String, String> _status = {};
  String? lastRejectReason;
  String? lastRejectReasonCode;
  String? lastPortalQueueEntryId;

  SanctionReviewResult _seal(String id, String status) {
    if (_status.containsKey(id)) {
      throw IdempotencyProcessingException(
        idempotencyKey: id,
        commandPath: 'review',
      );
    }
    _status[id] = status;
    return SanctionReviewResult(
      ledgerEntryId: 'l-$id',
      finalQueueStatus: status,
    );
  }

  String? lastApproveReasonCode;
  String? lastApproveReviewerReason;

  @override
  Future<SanctionReviewResult> approveSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
    String? reasonCode,
    String? reviewerReason,
  }) async {
    lastApproveReasonCode = reasonCode;
    lastApproveReviewerReason = reviewerReason;
    return _seal(queueEntryId, 'applied');
  }

  @override
  Future<SanctionReviewResult> rejectSanction({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required String rejectionReason,
    required String reasonCode,
    required DateTime occurredAtUtc,
  }) async {
    lastRejectReason = rejectionReason;
    lastRejectReasonCode = reasonCode;
    return _seal(queueEntryId, 'rejected');
  }

  @override
  Future<SanctionReviewResult> confirmPeerReview({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async => _seal(queueEntryId, 'applied');

  @override
  Future<SanctionReviewResult> declinePeerReview({
    required String organizationId,
    required String queueEntryId,
    required String reviewedByUserId,
    required String actorEmail,
    required String reason,
    required DateTime occurredAtUtc,
  }) async => SanctionReviewResult(
    ledgerEntryId: 'l-$queueEntryId',
    finalQueueStatus: 'pending',
  );

  @override
  Future<DisputeSanctionResult> disputeSanction({
    required String organizationId,
    required String queueEntryId,
    required String disputedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
  }) async => DisputeSanctionResult(
    ledgerEntryId: 'l-$queueEntryId',
    finalQueueStatus: 'disputed',
    resolutionDueAtUtc: occurredAtUtc.add(const Duration(days: 5)),
  );

  @override
  Future<String> generateDisputePortalToken({
    required String organizationId,
    required String queueEntryId,
    required String createdByUserId,
  }) async {
    lastPortalQueueEntryId = queueEntryId;
    return 'token-$queueEntryId';
  }
}

void main() {
  final now = DateTime.utc(2026, 6, 1);

  group('SanctionReviewCommandRepository (port contract)', () {
    test('approve seals to applied and carries the optional reason', () async {
      final repo = _FakeReview();
      final r = await repo.approveSanction(
        organizationId: 'org-1',
        queueEntryId: 'q-1',
        reviewedByUserId: 'u-1',
        actorEmail: 'a@x.com',
        occurredAtUtc: now,
        reasonCode: 'SENSOR_FAULT',
        reviewerReason: 'Laudo técnico anexado.',
      );
      expect(r.finalQueueStatus, 'applied');
      expect(repo.lastApproveReasonCode, 'SENSOR_FAULT');
      expect(repo.lastApproveReviewerReason, 'Laudo técnico anexado.');
    });

    test('reject carries the mandatory reason + structured code', () async {
      final repo = _FakeReview();
      await repo.rejectSanction(
        organizationId: 'org-1',
        queueEntryId: 'q-1',
        reviewedByUserId: 'u-1',
        actorEmail: 'a@x.com',
        rejectionReason: 'evidência insuficiente',
        reasonCode: 'SENSOR_FAULT',
        occurredAtUtc: now,
      );
      expect(repo.lastRejectReason, 'evidência insuficiente');
      expect(repo.lastRejectReasonCode, 'SENSOR_FAULT');
    });

    test('generateDisputePortalToken returns a token for the entry', () async {
      final repo = _FakeReview();
      final token = await repo.generateDisputePortalToken(
        organizationId: 'org-1',
        queueEntryId: 'q-1',
        createdByUserId: 'u-1',
      );
      expect(token, 'token-q-1');
      expect(repo.lastPortalQueueEntryId, 'q-1');
    });

    test('dispute seals disputed + an SLA deadline (INV-15)', () async {
      final repo = _FakeReview();
      final r = await repo.disputeSanction(
        organizationId: 'org-1',
        queueEntryId: 'q-1',
        disputedByUserId: 'u-1',
        actorEmail: 'a@x.com',
        occurredAtUtc: now,
      );
      expect(r.finalQueueStatus, 'disputed');
      expect(r.resolutionDueAtUtc.isAfter(now), isTrue);
    });

    test(
      'second verdict on an already-reviewed entry raises idempotency',
      () async {
        final repo = _FakeReview();
        await repo.approveSanction(
          organizationId: 'org-1',
          queueEntryId: 'q-1',
          reviewedByUserId: 'u-1',
          actorEmail: 'a@x.com',
          occurredAtUtc: now,
        );
        expect(
          () => repo.approveSanction(
            organizationId: 'org-1',
            queueEntryId: 'q-1',
            reviewedByUserId: 'u-2',
            actorEmail: 'b@x.com',
            occurredAtUtc: now,
          ),
          throwsA(isA<IdempotencyProcessingException>()),
        );
      },
    );
  });
}
