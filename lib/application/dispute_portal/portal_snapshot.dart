import 'package:equatable/equatable.dart';

/// One evidence item as projected by the `read_dispute_portal` RPC.
///
/// The RPC whitelists fields deliberately: NO org_id, uploader, or storage path.
class PortalEvidenceItem extends Equatable {
  final String id;
  final String fileName;
  final String mimeType;
  final int fileSizeBytes;
  final String sha256Hash;
  final String verificationStatus;
  final DateTime attachedAtUtc;

  const PortalEvidenceItem({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.sha256Hash,
    required this.verificationStatus,
    required this.attachedAtUtc,
  });

  factory PortalEvidenceItem.fromJson(Map<String, dynamic> json) {
    return PortalEvidenceItem(
      id: json['id'] as String,
      fileName: json['file_name'] as String? ?? 'evidence',
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ?? 0,
      sha256Hash: json['sha256_hash'] as String? ?? '',
      verificationStatus: json['verification_status'] as String? ?? 'PENDING',
      attachedAtUtc: DateTime.parse(json['attached_at'] as String).toUtc(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    fileName,
    mimeType,
    fileSizeBytes,
    sha256Hash,
    verificationStatus,
    attachedAtUtc,
  ];
}

/// Read-only snapshot served to an external carrier by `read_dispute_portal`.
///
/// [snapshotHash] is the SHA-256 the system sealed in the
/// `DISPUTE_PORTAL_TOKEN_ACCESSED` ledger fact — the value the carrier must echo
/// back to acknowledge ("De Acordo"). The fine amount is intentionally NOT part
/// of the served snapshot (information-disclosure guard in the RPC); the carrier
/// agrees to the penalty AS PRESENTED, bound by the hash.
class PortalSnapshot extends Equatable {
  final String status;
  final DateTime? disputedAtUtc;
  final DateTime? resolutionDueAtUtc;
  final String? ruleType;
  final String? description;
  final List<PortalEvidenceItem> evidence;
  final String snapshotHash;

  const PortalSnapshot({
    required this.status,
    required this.disputedAtUtc,
    required this.resolutionDueAtUtc,
    required this.ruleType,
    required this.description,
    required this.evidence,
    required this.snapshotHash,
  });

  /// True once the sanction is applied — the only state where "De Acordo" is
  /// offered (mirrors the `acknowledge_via_portal` gate).
  bool get isApplied => status == 'applied';

  /// True while disputed — counter-evidence submission is offered.
  bool get isDisputed => status == 'disputed';

  factory PortalSnapshot.fromJson(Map<String, dynamic> json) {
    final summary = json['dispute_summary'] as Map<String, dynamic>?;
    final verdict = json['verdict_summary'] as Map<String, dynamic>?;
    final evidenceJson = (json['evidence'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return PortalSnapshot(
      status: summary?['status'] as String? ?? 'unknown',
      disputedAtUtc: summary?['disputed_at'] != null
          ? DateTime.parse(summary!['disputed_at'] as String).toUtc()
          : null,
      resolutionDueAtUtc: summary?['resolution_due_at'] != null
          ? DateTime.parse(summary!['resolution_due_at'] as String).toUtc()
          : null,
      ruleType: verdict?['rule_type'] as String?,
      description: verdict?['description'] as String?,
      evidence: evidenceJson.map(PortalEvidenceItem.fromJson).toList(),
      snapshotHash: json['snapshot_hash'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
    status,
    disputedAtUtc,
    resolutionDueAtUtc,
    ruleType,
    description,
    evidence,
    snapshotHash,
  ];
}

/// Outcome of a counter-evidence submission (request → upload → finalize).
enum PortalSubmissionOutcome {
  pendingAudit,
  hashMismatch,
  mimeMismatch,
  rejected,
}

/// Typed failure for the external portal data path (no infra leakage to UI).
class PortalDisputeException implements Exception {
  final String message;
  final bool retryable;
  const PortalDisputeException(this.message, {this.retryable = false});
  @override
  String toString() =>
      'PortalDisputeException: $message (retryable: $retryable)';
}
