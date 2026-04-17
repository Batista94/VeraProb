import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Infrastructure implementation of [EvidenceStorageReader] for Supabase Storage (INV-13).
///
/// **Streaming-First:** all byte reads use [http.StreamedResponse] so that binary
/// data is never fully buffered in memory — OOM-safe for arbitrarily large files.
///
/// **206 Enforcement (Zero-Trust):** [readRange] aborts with an exception on any
/// non-206 HTTP status. There is NO linear-scan fallback — partial-content support
/// is a prerequisite for safe binary inspection (CX-05-v2.2).
///
/// **Authenticated HEAD:** [getContentLength] issues a JWT-authenticated HEAD
/// request so file sizes are always server-authoritative (INV-18).
class SupabaseEvidenceStorageReader implements EvidenceStorageReader {
  final SupabaseClient _client;
  final http.Client _httpClient;

  SupabaseEvidenceStorageReader(this._client, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  String get _bearerToken =>
      'Bearer ${_client.auth.currentSession?.accessToken ?? ''}';

  @override
  Stream<List<int>> streamBytes({required String url}) async* {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['Authorization'] = _bearerToken;

    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      await streamedResponse.stream.drain<void>();
      throw DomainException(
        'Failed to stream evidence: ${streamedResponse.statusCode} (URL: $url)',
      );
    }

    yield* streamedResponse.stream;
  }

  @override
  Future<List<int>> readRange({
    required String url,
    required int start,
    required int length,
  }) async {
    final end = start + length - 1;
    final request = http.Request('GET', Uri.parse(url))
      ..headers['Authorization'] = _bearerToken
      ..headers['Range'] = 'bytes=$start-$end';

    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 206) {
      await streamedResponse.stream.drain<void>();
      throw DomainException(
        'Range request not honored: expected 206 Partial Content but got '
        '${streamedResponse.statusCode}. Server does not support Range requests — '
        'binary inspection aborted (CX-05 Zero-Trust, URL: $url).',
      );
    }

    final bytes = <int>[];
    await for (final chunk in streamedResponse.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  @override
  Future<int> getContentLength({required String url}) async {
    final response = await _httpClient.head(
      Uri.parse(url),
      headers: {'Authorization': _bearerToken},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DomainException(
        'HEAD request failed: ${response.statusCode} (URL: $url)',
      );
    }

    final raw = response.headers['content-length'];
    if (raw == null) {
      throw DomainException(
        'Server did not return Content-Length header (URL: $url)',
      );
    }

    final length = int.tryParse(raw);
    if (length == null) {
      throw DomainException('Invalid Content-Length "$raw" (URL: $url)');
    }

    return length;
  }
}
