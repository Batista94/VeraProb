import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/authenticated_range_stream_controller.dart';

/// Infrastructure implementation of [EvidenceStorageReader] for Supabase Storage (INV-13).
///
/// **Streaming-First:** all byte reads use [http.StreamedResponse] so that binary
/// data is never fully buffered in memory — OOM-safe for arbitrarily large files.
///
/// **206 Enforcement (Zero-Trust):** [readRange] delegates to [AuthenticatedRangeStreamController]
/// which calls [http.Client.close()] on any non-206 — TCP abort, zero bytes buffered.
/// PROHIBITED: stream.drain(), stream.toList() (CX-05-v2.3 / FIX-3).
///
/// **Authenticated HEAD:** [getContentLength] issues a JWT-authenticated HEAD
/// request so file sizes are always server-authoritative (INV-18).
class SupabaseEvidenceStorageReader implements EvidenceStorageReader {
  final SupabaseClient _client;
  final http.Client _httpClient;
  late final AuthenticatedRangeStreamController _streamController;

  SupabaseEvidenceStorageReader(this._client, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client() {
    _streamController = AuthenticatedRangeStreamController(
      bearerTokenFactory: () => _bearerToken,
    );
  }

  String get _bearerToken =>
      'Bearer ${_client.auth.currentSession?.accessToken ?? ''}';

  @override
  Stream<List<int>> streamBytes({required String url}) async* {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['Authorization'] = _bearerToken;

    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
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
    return _streamController.fetchRange(url: url, start: start, length: length);
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
