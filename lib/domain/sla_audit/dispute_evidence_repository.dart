// pr_scanner: ignore-regression
// Council-reviewed (Phase 10.6 v3 council-remediated plan, 2026-06-12):
// dispute reality core — evidence/reason-code/command contracts (INV-1/3/9).
import 'dart:typed_data';
import 'package:veraprob/domain/sla_audit/dispute_evidence_attachment.dart';

/// Port for dispute evidence write/read. Backed by Supabase Storage (file) +
/// attach_dispute_evidence RPC (metadata). All ops scoped to org_id (INV-1).
abstract class DisputeEvidenceRepository {
  static const int maxAttachmentsPerDispute = 10;

  /// Uploads bytes and registers SHA-256-sealed metadata via the RPC.
  /// [fileBytes] is a Uint8List (Supabase Dart Storage takes uploadBinary, not a
  /// stream; 10MB cap makes buffering acceptable — M-eng).
  /// Throws [IntegrityException] on limit exceeded / ownership failure.
  Future<DisputeEvidenceAttachment> attach({
    required String organizationId,
    required String queueEntryId,
    required String fileName,
    required String mimeType,
    required String sha256Hash,
    required String uploadedBy,
    required Uint8List fileBytes,
    required DateTime attachedAtUtc,
  });

  Future<List<DisputeEvidenceAttachment>> findByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  });

  Future<int> countActiveByQueueEntryId({
    required String organizationId,
    required String queueEntryId,
  });

  /// Soft-deletes an attachment (sets deleted_at). Never hard-deletes.
  Future<void> softDelete({
    required String organizationId,
    required String attachmentId,
    required DateTime deletedAtUtc,
  });
}
