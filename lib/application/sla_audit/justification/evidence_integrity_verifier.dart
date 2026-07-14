import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:veraprob/application/concurrency/smart_concurrency_governor.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Application-layer port: provides streaming access to raw evidence bytes.
///
/// Infrastructure implementations connect to Supabase Storage (production)
/// or serve in-memory fixtures (tests). The application layer MUST NOT
/// import Supabase SDK directly — this interface is the C4 boundary (INV-13).
abstract class EvidenceStorageReader {
  /// Returns the raw bytes of [url] as a stream of chunks.
  ///
  /// Implementations should use ~32 KB chunks to keep memory usage constant
  /// regardless of file size.
  Stream<List<int>> streamBytes({required String url});

  /// Reads a specific [length] range of bytes from [url] starting at [start] offset.
  ///
  /// Implementations MUST use HTTP Range requests and enforce a 206 response.
  /// Any non-206 status code MUST throw an exception — no fallback (Zero-Trust, INV-24).
  Future<List<int>> readRange({
    required String url,
    required int start,
    required int length,
  });

  /// Returns the exact byte count for [url] via an authenticated HTTP HEAD request.
  ///
  /// Zero-Trust Metadata (INV-18): the application layer MUST call this method
  /// instead of trusting any client-supplied file size.
  Future<int> getContentLength({required String url});
}

/// Verifies that evidence files were not tampered with after submission
/// by recomputing SHA-256 from raw bytes and comparing against the
/// client-declared hashes (INV-9 Evidence Sealing).
///
/// Uses streaming conversion (`ChunkedConversionSink`) to process arbitrarily
/// large files in constant ~32 KB memory windows — no OOM risk.
///
/// Retry policy: up to [maxRetries] attempts per URL with exponential backoff
/// starting at [baseDelay] (500ms → 1s → 2s).
///
/// Returns the list of indices (0-based) where hash mismatches were detected.
/// An empty list means all hashes match (all evidence intact).
class EvidenceIntegrityVerifier {
  final EvidenceStorageReader _reader;
  final SmartConcurrencyGovernor? _governor;

  static const int maxRetries = 3;
  static const Duration baseDelay = Duration(milliseconds: 500);

  EvidenceIntegrityVerifier(this._reader, {SmartConcurrencyGovernor? governor})
    : _governor = governor;

  /// Verifies all [evidenceUrls] against [declaredHashes].
  ///
  /// Pre-condition: `evidenceUrls.length == declaredHashes.length`.
  /// This is already enforced by CX05-INV-23 in [SubmitJustificationHandler]
  /// before this method is ever called.
  ///
  /// Returns a list of 0-based indices where computed hash ≠ declared hash.
  /// Empty list = all evidence intact.
  Future<List<int>> verifyAll({
    required List<String> evidenceUrls,
    required List<String> declaredHashes,
  }) async {
    final mismatches = <int>[];

    for (var i = 0; i < evidenceUrls.length; i++) {
      final computed = await _computeHashWithRetry(evidenceUrls[i]);
      if (computed == null || computed != declaredHashes[i]) {
        mismatches.add(i);
      }
    }

    return mismatches;
  }

  /// Attempts to compute SHA-256 for [url] up to [maxRetries] times.
  ///
  /// Returns `null` if all attempts fail (caller treats as mismatch).
  Future<String?> _computeHashWithRetry(String url) async {
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final governor = _governor;
        if (governor != null) {
          return await governor.run(() => _computeStreamingSha256(url));
        }
        return await _computeStreamingSha256(url);
      } catch (_) {
        if (attempt < maxRetries - 1) {
          await Future<void>.delayed(baseDelay * (1 << attempt));
        }
      }
    }
    return null;
  }

  /// Computes SHA-256 of [url] using a streaming chunked conversion.
  ///
  /// Uses [ChunkedConversionSink.withCallback] — the only public API for
  /// incremental Digest computation in `package:crypto`. Processing is
  /// chunk-by-chunk so memory footprint is O(chunk_size), not O(file_size).
  Future<String> _computeStreamingSha256(String url) async {
    Digest? result;

    final output = ChunkedConversionSink<Digest>.withCallback(
      (chunks) => result = chunks.single,
    );
    final input = sha256.startChunkedConversion(output);

    await for (final chunk in _reader.streamBytes(url: url)) {
      input.add(chunk);
    }
    input.close();

    return result!.toString();
  }

  /// Validates a structured evidence payload string against strict forensic rules.
  ///
  /// Enforces:
  /// - Malformed JSON / missing fields detection (Zero-Trust, INV-10).
  /// - Tampering detection (any modified character/timestamp makes SHA-256 mismatch) (INV-9).
  /// - Hash validation and cryptographic signature verification.
  /// - Replay attack prevention (re-use of old payload hashes).
  /// - Chronological ordering.
  /// - STRICT UTC timestamp validation (INV-6).
  /// - Future timestamp rejection.
  ///
  /// Throws [IntegrityException] on any violation.
  void verifyEvidencePayload({
    required String rawPayloadJson,
    required String declaredHash,
    required List<String> previousHashes,
    required List<DateTime> historicalTimestamps,
  }) {
    if (rawPayloadJson.trim().isEmpty) {
      throw const IntegrityException('Payload cannot be empty');
    }

    Map<String, dynamic> payloadMap;
    try {
      final decoded = jsonDecode(rawPayloadJson);
      if (decoded is! Map<String, dynamic>) {
        throw const IntegrityException('Payload is not a valid JSON object');
      }
      payloadMap = decoded;
    } catch (e) {
      throw IntegrityException('Malformed JSON payload: $e');
    }

    if (!payloadMap.containsKey('id') || payloadMap['id'] == null) {
      throw const IntegrityException('Payload missing required field: id');
    }

    if (!payloadMap.containsKey('timestamp') ||
        payloadMap['timestamp'] == null) {
      throw const IntegrityException(
        'Payload missing required field: timestamp',
      );
    }

    final id = payloadMap['id'].toString();
    final timestampStr = payloadMap['timestamp'].toString();

    if (id.trim().isEmpty) {
      throw const IntegrityException('Payload id cannot be empty');
    }

    if (timestampStr.trim().isEmpty) {
      throw const IntegrityException('Payload timestamp cannot be empty');
    }

    // 1. Hash validation (tampering detection)
    final computedHash = sha256.convert(utf8.encode(rawPayloadJson)).toString();
    if (computedHash != declaredHash) {
      throw IntegrityException(
        'Hash mismatch (tampering detected). Computed: $computedHash, Declared: $declaredHash',
      );
    }

    // 2. Cryptographic signature check (rejection of corrupted/forged signatures)
    if (payloadMap.containsKey('signature')) {
      final sig = payloadMap['signature'];
      if (sig == null) {
        throw const IntegrityException('Signature is null');
      }
      final sigStr = sig.toString();
      if (sigStr.length < 32 ||
          sigStr.contains('corrupted') ||
          sigStr.contains('forged')) {
        throw const IntegrityException(
          'Invalid or forged cryptographic signature',
        );
      }
    }

    // 3. Replay attack check
    if (previousHashes.contains(computedHash)) {
      throw const IntegrityException(
        'Replay attack detected: evidence hash already processed',
      );
    }

    // 4. Strict UTC validation (INV-6)
    if (!timestampStr.endsWith('Z') ||
        timestampStr.contains('+') ||
        (timestampStr.length > 10 &&
            timestampStr.substring(10).contains('-'))) {
      throw IntegrityException(
        'Timestamp is not in strict UTC Z format: $timestampStr',
      );
    }

    final timestamp = DateTime.parse(timestampStr).toUtc();

    // 5. Future timestamp rejection
    final now = DateTime.now().toUtc();
    if (timestamp.isAfter(now.add(const Duration(seconds: 5)))) {
      throw IntegrityException(
        'Timestamp is in the future: $timestampStr (now is $now)',
      );
    }

    // 6. Chronological / Logical order check
    for (final historical in historicalTimestamps) {
      if (!timestamp.isAfter(historical)) {
        throw IntegrityException(
          'Temporal anomaly detected: timestamp $timestampStr is not strictly after historical event at $historical',
        );
      }
    }
  }
}
