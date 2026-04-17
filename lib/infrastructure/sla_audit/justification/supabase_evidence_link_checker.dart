import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';

/// Infrastructure implementation of [EvidenceLinkChecker] for Supabase Storage (INV-13).
///
/// Issues HTTP HEAD requests with JWT authorization to verify file existence
/// and properties without downloading the body.
class SupabaseEvidenceLinkChecker implements EvidenceLinkChecker {
  final SupabaseClient _client;
  final http.Client _httpClient;

  SupabaseEvidenceLinkChecker(this._client, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  @override
  Future<EvidenceValidationResult> checkLink(String url) async {
    try {
      final response = await _httpClient.head(
        Uri.parse(url),
        headers: {
          'Authorization':
              'Bearer ${_client.auth.currentSession?.accessToken ?? ''}',
        },
      );

      final status = _mapHttpStatus(response.statusCode);
      final length = int.tryParse(response.headers['content-length'] ?? '');
      final acceptRanges = response.headers['accept-ranges'] == 'bytes';

      return EvidenceValidationResult(
        url: url,
        status: status,
        httpStatusCode: response.statusCode,
        contentLength: length,
        acceptRanges: acceptRanges,
      );
    } catch (_) {
      return EvidenceValidationResult(
        url: url,
        status: EvidenceLinkStatus.error,
      );
    }
  }

  EvidenceLinkStatus _mapHttpStatus(int code) {
    if (code >= 200 && code < 300) return EvidenceLinkStatus.available;
    if (code == 404) return EvidenceLinkStatus.missing;
    if (code == 401 || code == 403) return EvidenceLinkStatus.forbidden;
    return EvidenceLinkStatus.error;
  }
}
