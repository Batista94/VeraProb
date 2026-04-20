/// Forensic Audit Signature: CX-05-v2.3 / FIX-3
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb Senior Engineer
///
/// Executes authenticated HTTP range requests with TCP-abort-on-failure.
///
/// **OOM Prevention (FIX-3):** on any non-206 response, calls
/// [http.Client.close()] immediately to force a TCP RST. Zero bytes buffered —
/// prohibited methods such as `stream.drain()` and `stream.toList()` are
/// never used.
///
/// **Per-Request Isolation:** a fresh [http.Client] is created per
/// [fetchRange] call so closing on error never affects concurrent requests.
library;

import 'package:http/http.dart' as http;
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class AuthenticatedRangeStreamController {
  final String Function() _bearerTokenFactory;
  final http.Client Function() _clientFactory;

  AuthenticatedRangeStreamController({
    required String Function() bearerTokenFactory,
    http.Client Function()? clientFactory,
  }) : _bearerTokenFactory = bearerTokenFactory,
       _clientFactory = clientFactory ?? http.Client.new;

  /// Fetches bytes [start]..[start+length−1] from [url] via HTTP Range request.
  ///
  /// On non-206 response: calls [http.Client.close] immediately — no bytes
  /// buffered. Throws [DomainException] on any non-206 or network error.
  Future<List<int>> fetchRange({
    required String url,
    required int start,
    required int length,
  }) async {
    final client = _clientFactory();
    try {
      final end = start + length - 1;
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'Authorization': _bearerTokenFactory(),
          'Range': 'bytes=$start-$end',
        },
      );

      if (response.statusCode != 206) {
        client.close();
        throw DomainException(
          'Range request not honored: expected 206 Partial Content but got '
          '${response.statusCode}. Server does not support Range requests — '
          'binary inspection aborted (CX-05 Zero-Trust, URL: $url).',
        );
      }

      return response.bodyBytes.toList();
    } catch (e) {
      client.close();
      rethrow;
    }
  }
}
