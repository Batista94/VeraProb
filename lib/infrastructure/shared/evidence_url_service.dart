import 'package:veraprob/infrastructure/config/environment.dart';

/// Service to encapsulate Supabase evidence URL generation.
///
/// **INV-26 (Secure Proxy Mandatory):**
/// All evidence (photos, audio) MUST be served via the `secure-evidence-proxy`
/// edge function to ensure JWT-authenticated access to private storage buckets.
/// UI widgets MUST NOT construct these URLs manually (SRP compliance).
class EvidenceUrlService {
  const EvidenceUrlService();

  /// Generates the secure proxy URL for a given evidence ID.
  String getProxyUrl(String evidenceId) {
    if (evidenceId.isEmpty) return '';
    return '${EnvironmentConfig.supabaseUrl}/functions/v1/secure-evidence-proxy?evidence_id=$evidenceId';
  }

  /// Generates the auditor dispute-evidence proxy URL for a dispute attachment.
  ///
  /// Served by the `auditor-dispute-evidence` edge function (bucket
  /// `dispute_evidence`), which enforces JWT + TENANT_ADMIN/AUDITOR role +
  /// org-scope and strips EXIF (INV-18). UI MUST NOT build this URL manually.
  String getDisputeAttachmentProxyUrl(String attachmentId) {
    if (attachmentId.isEmpty) return '';
    return '${EnvironmentConfig.supabaseUrl}/functions/v1/auditor-dispute-evidence?attachment_id=$attachmentId';
  }
}
