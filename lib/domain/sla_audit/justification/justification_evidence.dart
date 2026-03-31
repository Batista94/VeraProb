import 'package:equatable/equatable.dart';

/// Forensic evidence file attached to a [ContractorJustification].
///
/// Fully immutable value object — no copyWith (INV-7, INV-8).
/// [contentHash] is the SHA-256 hex digest computed server-side before storage.
class JustificationEvidence extends Equatable {
  final String id;
  final String justificationId;
  final String organizationId;
  final String fileName;

  /// SHA-256 hex digest (64 characters) computed server-side (INV-8).
  final String contentHash;

  final String storagePath;
  final DateTime uploadedAtUtc;

  const JustificationEvidence({
    required this.id,
    required this.justificationId,
    required this.organizationId,
    required this.fileName,
    required this.contentHash,
    required this.storagePath,
    required this.uploadedAtUtc,
  });

  @override
  List<Object?> get props => [
    id,
    justificationId,
    organizationId,
    fileName,
    contentHash,
    storagePath,
    uploadedAtUtc,
  ];
}
