import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_repository.dart';

/// In-memory implementation of [DisputeEvidenceRepository].
///
/// Reproduces the `attach_dispute_evidence` RPC guards against an in-memory map
/// so in-memory persistence mode and widget tests exercise the same boundaries:
///   - INV-9 seal validation via [DisputeEvidenceAttachment.validated];
///   - ADD-3 10-attachment cap → [IntegrityException] (mirrors RPC P0001);
///   - tenant isolation: a soft-delete on an attachment outside the caller's org
///     is indistinguishable from not-found → [SovereigntyViolationException]
///     (INV-26 anti-oracle, mirrors the RPC's 42501).
class InMemoryDisputeEvidenceRepository implements DisputeEvidenceRepository {
  static const _uuid = Uuid();
  final Map<String, DisputeEvidenceAttachment> _store = {};

  static const _extByMime = <String, String>{
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'application/pdf': '.pdf',
    'image/heic': '.heic',
    'image/heif': '.heif',
    'image/webp': '.webp',
  };

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
    final active = await countActiveByQueueEntryId(
      organizationId: organizationId,
      queueEntryId: queueEntryId,
    );
    if (active >= DisputeEvidenceRepository.maxAttachmentsPerDispute) {
      throw const IntegrityException('Evidence attachment limit reached.');
    }

    final id = _uuid.v4();
    final ext = _extByMime[mimeType] ?? '';
    final attachment = DisputeEvidenceAttachment.validated(
      id: id,
      organizationId: organizationId,
      queueEntryId: queueEntryId,
      storagePath: '$organizationId/$queueEntryId/$id$ext',
      fileName: fileName,
      mimeType: mimeType,
      fileSizeBytes: fileBytes.length,
      sha256Hash: sha256Hash,
      verificationStatus: EvidenceVerificationStatus.pending,
      hashVerifiedAtUtc: null,
      uploadedBy: uploadedBy,
      attachedAtUtc: attachedAtUtc,
      deletedAtUtc: null,
    );
    _store[id] = attachment;
    return attachment;
  }

  @override
  Future<List<DisputeEvidenceAttachment>> findByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) async {
    final rows =
        _store.values
            .where(
              (a) =>
                  a.organizationId == organizationId &&
                  a.queueEntryId == queueEntryId &&
                  a.deletedAtUtc == null,
            )
            .toList()
          ..sort((a, b) => a.attachedAtUtc.compareTo(b.attachedAtUtc));
    return List.unmodifiable(rows);
  }

  @override
  Future<int> countActiveByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) async {
    return _store.values
        .where(
          (a) =>
              a.organizationId == organizationId &&
              a.queueEntryId == queueEntryId &&
              a.deletedAtUtc == null,
        )
        .length;
  }

  @override
  Future<void> softDelete({
    required String organizationId,
    required String attachmentId,
    required DateTime deletedAtUtc,
  }) async {
    final current = _store[attachmentId];
    if (current == null || current.organizationId != organizationId) {
      throw SovereigntyViolationException(
        payloadOrgId: organizationId,
        jwtOrgId: organizationId,
        message: 'Evidence rejected.',
      );
    }
    _store[attachmentId] = DisputeEvidenceAttachment(
      id: current.id,
      organizationId: current.organizationId,
      queueEntryId: current.queueEntryId,
      storagePath: current.storagePath,
      fileName: current.fileName,
      mimeType: current.mimeType,
      fileSizeBytes: current.fileSizeBytes,
      sha256Hash: current.sha256Hash,
      verificationStatus: current.verificationStatus,
      hashVerifiedAtUtc: current.hashVerifiedAtUtc,
      uploadedBy: current.uploadedBy,
      attachedAtUtc: current.attachedAtUtc,
      deletedAtUtc: deletedAtUtc.toUtc(),
    );
  }
}
