import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Entity: cryptographic evidence attachment for a disputed sanction.
///
/// Modeled as an Entity (own id, lifecycle via [deletedAtUtc], provenance).
/// Sealed at ingest (INV-9): [sha256Hash] computed client-side from raw bytes
/// BEFORE upload, re-verified server-side (ADD-2) → [verificationStatus].
/// Equality covers ALL structural fields so two rows with the same id but a
/// different hash are NOT equal (prevents a hash-swap masking attack in sets).
enum EvidenceVerificationStatus { pending, verified, mismatch }

class DisputeEvidenceAttachment extends Equatable {
  final String id;
  final String organizationId;
  final String queueEntryId;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int fileSizeBytes;
  final String sha256Hash; // INV-9: 64-char lowercase hex
  final EvidenceVerificationStatus verificationStatus;
  final DateTime? hashVerifiedAtUtc;
  final String uploadedBy;
  final DateTime attachedAtUtc;
  final DateTime? deletedAtUtc;

  const DisputeEvidenceAttachment({
    required this.id,
    required this.organizationId,
    required this.queueEntryId,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.sha256Hash,
    required this.verificationStatus,
    required this.hashVerifiedAtUtc,
    required this.uploadedBy,
    required this.attachedAtUtc,
    required this.deletedAtUtc,
  });

  factory DisputeEvidenceAttachment.validated({
    required String id,
    required String organizationId,
    required String queueEntryId,
    required String storagePath,
    required String fileName,
    required String mimeType,
    required int fileSizeBytes,
    required String sha256Hash,
    required EvidenceVerificationStatus verificationStatus,
    required DateTime? hashVerifiedAtUtc,
    required String uploadedBy,
    required DateTime attachedAtUtc,
    required DateTime? deletedAtUtc,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hash)) {
      throw const IntegrityException('SHA-256 hash format invalid (INV-9).');
    }
    if (fileSizeBytes <= 0 || fileSizeBytes > 10485760) {
      throw const IntegrityException('File size must be 1B-10MB.');
    }
    const allowedMimes = {
      'image/jpeg',
      'image/png',
      'application/pdf',
      'image/heic',
      'image/heif',
      'image/webp',
    };
    if (!allowedMimes.contains(mimeType)) {
      throw IntegrityException('MIME type "$mimeType" not allowed.');
    }
    if (!attachedAtUtc.isUtc) {
      throw const IntegrityException('attachedAtUtc must be UTC (INV-6).');
    }
    return DisputeEvidenceAttachment(
      id: id,
      organizationId: organizationId,
      queueEntryId: queueEntryId,
      storagePath: storagePath,
      fileName: fileName,
      mimeType: mimeType,
      fileSizeBytes: fileSizeBytes,
      sha256Hash: sha256Hash,
      verificationStatus: verificationStatus,
      hashVerifiedAtUtc: hashVerifiedAtUtc,
      uploadedBy: uploadedBy,
      attachedAtUtc: attachedAtUtc,
      deletedAtUtc: deletedAtUtc,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    queueEntryId,
    storagePath,
    fileName,
    mimeType,
    fileSizeBytes,
    sha256Hash,
    verificationStatus,
    hashVerifiedAtUtc,
    uploadedBy,
    attachedAtUtc,
    deletedAtUtc,
  ];
}
