import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres + Storage implementation of [DisputeEvidenceRepository].
///
/// Two-step atomic-enough write (M-eng): bytes land in the private
/// `dispute_evidence` bucket first (RLS gates the `{org_id}` path segment), then
/// the sealed metadata row is registered EXCLUSIVELY via the
/// `attach_dispute_evidence` SECURITY DEFINER RPC (B4 ownership + path match +
/// H2 advisory-lock + 10-attachment count). An orphan blob (upload ok, RPC
/// rejected) is unreachable by the app and swept by the LGPD lifecycle job — it
/// never becomes evidence because the metadata row is the source of truth.
///
/// **Error mapping** (via [BasePostgresRepository.withErrorHandler]):
/// - RPC `P0001` (10-attachment limit) → [IntegrityException] (message intact).
/// - RPC `42501` (wrong org / wrong role / path mismatch / not-disputed) →
///   opaque [SovereigntyViolationException] (INV-26 anti-oracle).
class PostgresDisputeEvidenceRepository extends BasePostgresRepository
    implements DisputeEvidenceRepository {
  PostgresDisputeEvidenceRepository(super.client);

  static const _bucket = 'dispute_evidence';
  static const _uuid = Uuid();

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
    // Pre-validate at the boundary so a malformed seal never costs a 10MB upload.
    final ext = _extByMime[mimeType];
    if (ext == null) {
      throw IntegrityException('MIME type "$mimeType" not allowed.');
    }
    final storagePath = '$organizationId/$queueEntryId/${_uuid.v4()}$ext';

    return withErrorHandler('dispute_evidence', null, () async {
      // 1. Upload the immutable blob (private bucket, no overwrite).
      await client.storage
          .from(_bucket)
          .uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );

      // 2. Register sealed metadata via the ownership-checked RPC (the ONLY
      //    insert path — there is no direct INSERT policy on the table).
      final attachmentId = await client.rpc<String>(
        'attach_dispute_evidence',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
          'p_storage_path': storagePath,
          'p_file_name': fileName,
          'p_mime_type': mimeType,
          'p_file_size_bytes': fileBytes.length,
          'p_sha256_hash': sha256Hash,
          'p_uploaded_by': uploadedBy,
          'p_attached_at_utc': attachedAtUtc.toUtc().toIso8601String(),
        },
      );

      // Final seal: re-asserts INV-9 hash format + size + MIME + UTC client-side.
      return DisputeEvidenceAttachment.validated(
        id: attachmentId,
        organizationId: organizationId,
        queueEntryId: queueEntryId,
        storagePath: storagePath,
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
    });
  }

  @override
  Future<List<DisputeEvidenceAttachment>> findByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) {
    return withErrorHandler('dispute_evidence', queueEntryId, () async {
      final rows = await client
          .from('dispute_evidence_attachments')
          .select()
          .eq('organization_id', organizationId)
          .eq('queue_entry_id', queueEntryId)
          .isFilter('deleted_at', null)
          .order('attached_at');
      return rows.map((r) => mapRow(r)).toList(growable: false);
    });
  }

  @override
  Future<int> countActiveByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  }) {
    return withErrorHandler('dispute_evidence', queueEntryId, () async {
      final rows = await client
          .from('dispute_evidence_attachments')
          .select('id')
          .eq('organization_id', organizationId)
          .eq('queue_entry_id', queueEntryId)
          .isFilter('deleted_at', null);
      return rows.length;
    });
  }

  @override
  Future<void> softDelete({
    required String organizationId,
    required String attachmentId,
    required DateTime deletedAtUtc,
  }) {
    return withErrorHandler('dispute_evidence', attachmentId, () async {
      await client
          .from('dispute_evidence_attachments')
          .update({'deleted_at': deletedAtUtc.toUtc().toIso8601String()})
          .eq('organization_id', organizationId)
          .eq('id', attachmentId);
    });
  }

  @visibleForTesting
  static DisputeEvidenceAttachment mapRow(Map<String, dynamic> row) {
    final verifiedAt = row['hash_verified_at'] as String?;
    final deletedAt = row['deleted_at'] as String?;
    return DisputeEvidenceAttachment(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      queueEntryId: row['queue_entry_id'] as String,
      storagePath: row['storage_path'] as String,
      fileName: row['file_name'] as String,
      mimeType: row['mime_type'] as String,
      fileSizeBytes: (row['file_size_bytes'] as num).toInt(),
      sha256Hash: row['sha256_hash'] as String,
      verificationStatus: _statusFromDb(row['verification_status'] as String),
      hashVerifiedAtUtc: verifiedAt == null
          ? null
          : DateTime.parse(verifiedAt).toUtc(),
      uploadedBy: row['uploaded_by'] as String,
      attachedAtUtc: DateTime.parse(row['attached_at'] as String).toUtc(),
      deletedAtUtc: deletedAt == null
          ? null
          : DateTime.parse(deletedAt).toUtc(),
    );
  }

  static EvidenceVerificationStatus _statusFromDb(String raw) => switch (raw) {
    'VERIFIED' => EvidenceVerificationStatus.verified,
    'MISMATCH' => EvidenceVerificationStatus.mismatch,
    _ => EvidenceVerificationStatus.pending,
  };
}
