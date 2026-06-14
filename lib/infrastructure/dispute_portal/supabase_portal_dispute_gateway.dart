import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';

/// Supabase-backed [PortalDisputeGateway] for the anon (no-JWT) carrier portal.
///
/// Reads/acknowledges via SECURITY DEFINER RPCs (granted to anon) and submits
/// counter-evidence through the two portal edge functions. The carrier-declared
/// SHA-256 is advisory: the server recomputes it at finalize (INV-9).
class SupabasePortalDisputeGateway implements PortalDisputeGateway {
  final SupabaseClient _client;
  final http.Client _http;

  SupabasePortalDisputeGateway(this._client, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  @override
  Future<PortalSnapshot> read(String token) async {
    try {
      final result = await _client.rpc<dynamic>(
        'read_dispute_portal',
        params: {'p_token': token},
      );
      if (result is! Map) {
        throw const PortalDisputeException('Resposta inválida do portal.');
      }
      return PortalSnapshot.fromJson(Map<String, dynamic>.from(result));
    } on PortalDisputeException {
      rethrow;
    } catch (_) {
      // INV-26: every failure (not found / expired / revoked) looks identical.
      throw const PortalDisputeException('Link inválido ou expirado.');
    }
  }

  @override
  Future<void> acknowledge({
    required String token,
    required String snapshotHash,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'acknowledge_via_portal',
        params: {'p_token': token, 'p_snapshot_hash': snapshotHash},
      );
    } catch (_) {
      throw const PortalDisputeException(
        'Não foi possível registrar o aceite. Recarregue e tente novamente.',
      );
    }
  }

  @override
  Future<PortalSubmissionOutcome> submitEvidence({
    required String token,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final sha = sha256.convert(bytes).toString();

    // ── Phase 1: request signed upload URL ──────────────────────────────────
    final requestRes = await _client.functions.invoke(
      'portal-submit-request',
      body: {
        'token': token,
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSizeBytes': bytes.length,
        'sha256Client': sha,
      },
    );
    if (requestRes.status != 200) {
      throw const PortalDisputeException(
        'Envio recusado. Verifique o arquivo.',
      );
    }
    final reqData = requestRes.data;
    if (reqData is! Map) {
      throw const PortalDisputeException('Resposta inválida do servidor.');
    }
    final submissionId = reqData['submissionId'] as String?;
    final signedUrl = reqData['signedUrl'] as String?;
    if (submissionId == null || signedUrl == null) {
      throw const PortalDisputeException('Resposta inválida do servidor.');
    }

    // ── Phase 1.5: PUT bytes to the quarantine signed URL ─────────────────────
    final putRes = await _http.put(
      Uri.parse(signedUrl),
      headers: {'content-type': mimeType, 'x-upsert': 'false'},
      body: bytes,
    );
    if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
      throw const PortalDisputeException('Falha no envio do arquivo.');
    }

    // ── Phase 2: finalize (server-side magic-byte + SHA-256 verification) ─────
    final finalizeRes = await _client.functions.invoke(
      'portal-finalize-upload',
      body: {'token': token, 'submissionId': submissionId},
    );
    if (finalizeRes.status == 200) {
      return PortalSubmissionOutcome.pendingAudit;
    }
    final msg = _errorMessage(finalizeRes.data).toLowerCase();
    if (msg.contains('hash')) return PortalSubmissionOutcome.hashMismatch;
    if (msg.contains('type') || msg.contains('mime')) {
      return PortalSubmissionOutcome.mimeMismatch;
    }
    return PortalSubmissionOutcome.rejected;
  }

  String _errorMessage(dynamic data) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map && decoded['error'] is String) {
          return decoded['error'] as String;
        }
      } catch (_) {
        return data;
      }
    }
    return '';
  }
}
