/// Possible outcomes when checking an evidence URL's availability.
enum EvidenceLinkStatus {
  /// HTTP 200 — file accessible.
  available,

  /// HTTP 404 / DNS failure — file no longer exists.
  missing,

  /// HTTP 403 / 401 — file exists but access is denied.
  forbidden,

  /// Any other HTTP status or network error.
  error,
}

/// Result of a single evidence link check.
class EvidenceValidationResult {
  final String url;
  final EvidenceLinkStatus status;

  /// Raw HTTP status code if the server responded; null on network error.
  final int? httpStatusCode;

  const EvidenceValidationResult({
    required this.url,
    required this.status,
    this.httpStatusCode,
  });
}

/// Application-layer port: checks whether an evidence URL is reachable.
///
/// Implementations issue an HTTP HEAD request to avoid downloading file bytes
/// (the integrity check via [EvidenceIntegrityVerifier] handles byte access).
/// This interface is the C4 boundary (INV-13) — infrastructure provides the
/// HTTP client; the application layer never imports `dart:io` or `package:http`
/// directly.
abstract class EvidenceLinkChecker {
  /// Checks the availability of [url] without downloading its content.
  Future<EvidenceValidationResult> checkLink(String url);
}

/// Validates the availability of all evidence links for a justification.
///
/// This is a **diagnostic service, not a gate.** Link failures produce a
/// warning on the reviewer's dashboard but do NOT block submission or review.
/// Rationale: a missing link may indicate post-submission storage policy
/// changes, not tampering — tampering is detected by [EvidenceIntegrityVerifier].
///
/// All checks run in parallel via [Future.wait] to minimise latency.
class EvidenceValidationService {
  final EvidenceLinkChecker _checker;

  EvidenceValidationService(this._checker);

  /// Returns one [EvidenceValidationResult] per URL in [evidenceUrls].
  /// Results are in the same order as the input list.
  Future<List<EvidenceValidationResult>> validateLinks(
    List<String> evidenceUrls,
  ) async {
    return Future.wait(evidenceUrls.map(_checker.checkLink));
  }
}
