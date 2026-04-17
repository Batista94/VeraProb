import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  static const int maxRetries = 3;
  static const Duration baseDelay = Duration(milliseconds: 500);

  EvidenceIntegrityVerifier(this._reader);

  /// Verifies all [evidenceUrls] against [declaredHashes].
  ///
  /// Pre-condition: `evidenceUrls.length == declaredHashes.length`.
  /// This is already enforced by CX05-INV-23 in [SLAJustificationManager]
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
}
