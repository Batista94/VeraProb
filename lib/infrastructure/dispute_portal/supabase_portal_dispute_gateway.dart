import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';

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
      final result = await _client
          .rpc<dynamic>('read_dispute_portal', params: {'p_token': token})
          .timeout(const Duration(seconds: 10));
      if (result is! Map) {
        throw const PortalDisputeException(
          'Resposta inválida do portal.',
          retryable: true,
        );
      }
      return PortalSnapshot.fromJson(Map<String, dynamic>.from(result));
    } on PortalDisputeException {
      rethrow;
    } on TimeoutException {
      throw const PortalDisputeException(
        'Tempo esgotado ao contatar o servidor. Tente novamente.',
        retryable: true,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const PortalDisputeException('Link inválido ou expirado.');
      }
      throw const PortalDisputeException(
        'Falha temporária de comunicação. Tente novamente.',
        retryable: true,
      );
    } catch (_) {
      throw const PortalDisputeException(
        'Erro inesperado de rede. Tente novamente.',
        retryable: true,
      );
    }
  }

  @override
  Future<InfractionContextProjection> readInfractionContext(
    String token,
  ) async {
    try {
      final result = await _client
          .rpc<dynamic>('read_infraction_context', params: {'p_token': token})
          .timeout(const Duration(seconds: 10));
      if (result is! Map) {
        throw const PortalDisputeException(
          'Resposta inválida do portal.',
          retryable: true,
        );
      }
      return InfractionContextProjection.fromJson(
        Map<String, dynamic>.from(result),
      );
    } on PortalDisputeException {
      rethrow;
    } on TimeoutException {
      throw const PortalDisputeException(
        'Tempo esgotado ao contatar o servidor. Tente novamente.',
        retryable: true,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const PortalDisputeException('Link inválido ou expirado.');
      }
      throw const PortalDisputeException(
        'Falha temporária de comunicação. Tente novamente.',
        retryable: true,
      );
    } catch (_) {
      throw const PortalDisputeException(
        'Erro inesperado de rede. Tente novamente.',
        retryable: true,
      );
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
    required String justification,
    StagedFile? file,
    required String? sha256Client,
  }) async {
    // ── Phase 1: request signed upload URL ──────────────────────────────────
    // The whole esteira is safe to retry end-to-end: a transient failure between
    // create and upload reuses the QUARANTINE row by (token, sha256) without
    // burning a submission slot (idempotency, migration 20260825000001). Infra
    // unavailability surfaces as 503 → retryable; a business rejection stays an
    // opaque non-retryable 404 (INV-26).
    final FunctionResponse requestRes;
    try {
      requestRes = await _client.functions.invoke(
        'portal-submit-request',
        body: {
          'token': token,
          'justification': justification,
          if (file != null) ...{
            'fileName': file.name,
            'mimeType': file.mimeType,
            'fileSizeBytes': file.sizeBytes,
            'sha256Client': sha256Client,
          },
        },
      );
    } catch (_) {
      throw const PortalDisputeException(
        'Falha temporária de comunicação. Tente novamente.',
        retryable: true,
      );
    }
    if (requestRes.status == 503) {
      throw const PortalDisputeException(
        'Serviço temporariamente indisponível. Tentando novamente…',
        retryable: true,
      );
    }
    if (requestRes.status != 200) {
      throw const PortalDisputeException('Envio recusado. Verifique os dados.');
    }
    final reqData = requestRes.data;
    if (reqData is! Map) {
      throw const PortalDisputeException('Resposta inválida do servidor.');
    }
    final submissionId = reqData['submissionId'] as String?;
    final signedUrl = reqData['signedUrl'] as String?;
    if (submissionId == null) {
      throw const PortalDisputeException('Resposta inválida do servidor.');
    }

    // ── Phase 1.5: PUT bytes to the quarantine signed URL ─────────────────────
    if (file != null && signedUrl != null) {
      final http.Response putRes;
      try {
        putRes = await _http.put(
          Uri.parse(signedUrl),
          headers: {'content-type': file.mimeType, 'x-upsert': 'false'},
          body: file.bytes,
        );
      } catch (_) {
        throw const PortalDisputeException(
          'Falha no envio do arquivo. Tente novamente.',
          retryable: true,
        );
      }
      if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
        // Storage 5xx is transient infra; a 4xx (e.g. an expired signed URL)
        // needs a fresh request rather than a blind retry.
        throw PortalDisputeException(
          'Falha no envio do arquivo.',
          retryable: putRes.statusCode >= 500,
        );
      }
    }

    // ── Phase 2: finalize (server-side magic-byte + SHA-256 verification) ─────
    final FunctionResponse finalizeRes;
    try {
      finalizeRes = await _client.functions.invoke(
        'portal-finalize-upload',
        body: {'token': token, 'submissionId': submissionId},
      );
    } catch (_) {
      throw const PortalDisputeException(
        'Falha temporária de comunicação. Tente novamente.',
        retryable: true,
      );
    }
    if (finalizeRes.status == 200) {
      return PortalSubmissionOutcome.pendingAudit;
    }
    if (finalizeRes.status == 503) {
      throw const PortalDisputeException(
        'Serviço temporariamente indisponível. Tentando novamente…',
        retryable: true,
      );
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
