import 'package:equatable/equatable.dart';

/// Auditor-facing view of a finalized portal evidence submission awaiting
/// review. Projected by the `list_portal_submissions` RPC — the quarantine
/// table itself is deny-all, so only these whitelisted columns ever reach the
/// client (no quarantine paths, no declared metadata leak).
class PortalSubmissionSummary extends Equatable {
  final String submissionId;
  final String? attachmentId;
  final String fileName;
  final String? mimeTypeDetected;
  final int? fileSizeBytesActual;
  final String? sha256Server;

  /// Carrier testimony submitted WITH the file (sealed at ingest, INV-3/9).
  /// NULL for legacy rows that predate justification capture.
  final String? justificationText;
  final String status;
  final DateTime? submittedAtUtc;
  final DateTime? finalizedAtUtc;

  const PortalSubmissionSummary({
    required this.submissionId,
    required this.attachmentId,
    required this.fileName,
    required this.mimeTypeDetected,
    required this.fileSizeBytesActual,
    required this.sha256Server,
    required this.justificationText,
    required this.status,
    required this.submittedAtUtc,
    required this.finalizedAtUtc,
  });

  factory PortalSubmissionSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parseUtc(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toUtc();
    return PortalSubmissionSummary(
      submissionId: json['submission_id'] as String,
      attachmentId: json['attachment_id'] as String?,
      fileName: json['file_name'] as String,
      mimeTypeDetected: json['mime_type_detected'] as String?,
      fileSizeBytesActual: (json['file_size_bytes_actual'] as num?)?.toInt(),
      sha256Server: json['sha256_server'] as String?,
      justificationText: json['justification_text'] as String?,
      status: json['status'] as String,
      submittedAtUtc: parseUtc(json['submitted_at_utc']),
      finalizedAtUtc: parseUtc(json['finalized_at_utc']),
    );
  }

  @override
  List<Object?> get props => [
    submissionId,
    attachmentId,
    fileName,
    mimeTypeDetected,
    fileSizeBytesActual,
    sha256Server,
    justificationText,
    status,
    submittedAtUtc,
    finalizedAtUtc,
  ];
}

/// Auditor-facing view of a testimony-only (file-optional) portal contest.
/// Projected by the `list_portal_justification_submissions` RPC over the
/// deny-all `portal_justification_submissions` table. There are no bytes — the
/// testimony itself is the evidence, sealed via [sha256JustificationSeal]
/// (INV-9). Read-only for the auditor (no per-item accept/reject).
class PortalJustificationSummary extends Equatable {
  final String justificationSubmissionId;
  final String justificationText;
  final String sha256JustificationSeal;
  final String status;
  final DateTime? submittedAtUtc;

  const PortalJustificationSummary({
    required this.justificationSubmissionId,
    required this.justificationText,
    required this.sha256JustificationSeal,
    required this.status,
    required this.submittedAtUtc,
  });

  factory PortalJustificationSummary.fromJson(Map<String, dynamic> json) {
    final submitted = json['submitted_at_utc'];
    return PortalJustificationSummary(
      justificationSubmissionId: json['justification_submission_id'] as String,
      justificationText: json['justification_text'] as String,
      sha256JustificationSeal: json['sha256_justification_seal'] as String,
      status: json['status'] as String,
      submittedAtUtc: submitted == null
          ? null
          : DateTime.parse(submitted as String).toUtc(),
    );
  }

  @override
  List<Object?> get props => [
    justificationSubmissionId,
    justificationText,
    sha256JustificationSeal,
    status,
    submittedAtUtc,
  ];
}

/// Auditor verdict on a single portal submission.
enum PortalAuditDecision { accept, reject }

extension PortalAuditDecisionRpc on PortalAuditDecision {
  /// RPC contract value (`audit_portal_submission(p_decision)`).
  String get rpcValue => switch (this) {
    PortalAuditDecision.accept => 'accept',
    PortalAuditDecision.reject => 'reject',
  };
}

/// Authenticated (JWT-bound) gateway for the auditor PENDING_AUDIT review panel.
/// Backed by `list_portal_submissions` + `audit_portal_submission` SECURITY
/// DEFINER RPCs (org + TENANT_ADMIN/AUDITOR gated server-side; INV-22/26).
abstract class PortalSubmissionAuditGateway {
  Future<List<PortalSubmissionSummary>> listPending({
    required String organizationId,
    required String queueEntryId,
  });

  /// Testimony-only (file-optional) contests awaiting review. Backed by
  /// `list_portal_justification_submissions` (org + TENANT_ADMIN/AUDITOR gated).
  Future<List<PortalJustificationSummary>> listPendingJustifications({
    required String organizationId,
    required String queueEntryId,
  });

  Future<void> audit({
    required String organizationId,
    required String submissionId,
    required PortalAuditDecision decision,
    required String auditedByUserId,
  });
}
