import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_repository.dart';

class _FakeEvidence implements DisputeEvidenceRepository {
  final List<DisputeEvidenceAttachment> store = [];
  String? softDeletedId;

  @override
  Future<DisputeEvidenceAttachment> attach({
    required String organizationId,
    required String queueEntryId,
    required String fileName,
    required String mimeType,
    required String sha256Hash,
    required String uploadedBy,
    required Uint8List fileBytes,
    required DateTime attachedAtUtc,
  }) async {
    final a = DisputeEvidenceAttachment.validated(
      id: 'att-${store.length}',
      organizationId: organizationId,
      queueEntryId: queueEntryId,
      storagePath: '$organizationId/$queueEntryId/file',
      fileName: fileName,
      mimeType: mimeType,
      fileSizeBytes: fileBytes.length,
      sha256Hash: sha256Hash,
      verificationStatus: EvidenceVerificationStatus.verified,
      hashVerifiedAtUtc: attachedAtUtc,
      uploadedBy: uploadedBy,
      attachedAtUtc: attachedAtUtc,
      deletedAtUtc: null,
    );
    store.add(a);
    return a;
  }

  @override
  Future<List<DisputeEvidenceAttachment>> findByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) async => store
      .where(
        (a) =>
            a.organizationId == organizationId &&
            a.queueEntryId == queueEntryId,
      )
      .toList();

  @override
  Future<int> countActiveByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) async => store.where((a) => a.deletedAtUtc == null).length;

  @override
  Future<void> softDelete({
    required String organizationId,
    required String attachmentId,
    required DateTime deletedAtUtc,
  }) async {
    softDeletedId = attachmentId;
  }
}

void main() {
  group('DisputeEvidenceRepository (port contract)', () {
    test('exposes the per-dispute attachment cap = 10', () {
      expect(DisputeEvidenceRepository.maxAttachmentsPerDispute, 10);
    });

    test(
      'attach stores a sealed attachment and find/count reflect it',
      () async {
        final repo = _FakeEvidence();
        await repo.attach(
          organizationId: 'org-1',
          queueEntryId: 'q-1',
          fileName: 'doc.pdf',
          mimeType: 'application/pdf',
          sha256Hash: 'a' * 64,
          uploadedBy: 'u-1',
          fileBytes: Uint8List.fromList(List.filled(2048, 1)),
          attachedAtUtc: DateTime.utc(2026, 6, 2),
        );
        expect(
          await repo.countActiveByQueueEntryId(
            organizationId: 'org-1',
            queueEntryId: 'q-1',
          ),
          1,
        );
        final found = await repo.findByQueueEntryId(
          organizationId: 'org-1',
          queueEntryId: 'q-1',
        );
        expect(found.single.sha256Hash, 'a' * 64);
      },
    );

    test('softDelete records the target (never hard-deletes)', () async {
      final repo = _FakeEvidence();
      await repo.softDelete(
        organizationId: 'org-1',
        attachmentId: 'att-1',
        deletedAtUtc: DateTime.utc(2026, 6, 3),
      );
      expect(repo.softDeletedId, 'att-1');
    });
  });
}
