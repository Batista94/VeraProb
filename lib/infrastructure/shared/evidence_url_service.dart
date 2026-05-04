import 'package:veraprob/core/config/environment.dart';

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
}
