import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// Invokes a portal edge function. Returns a 2xx [FunctionResponse] or throws
/// [FunctionException] (status, details, reasonPhrase) for any non-2xx — the
/// exact contract of `functions_client`'s `invoke`. Infra-private (no app/feature
/// import); seam exists solely to unit-test [SupabasePortalDisputeGateway].
typedef EdgeFunctionInvoker =
    Future<FunctionResponse> Function(String name, {Object? body});

class SupabasePortalDisputeGateway implements PortalDisputeGateway {
  final SupabaseClient _client;
  final EdgeFunctionInvoker _invoke;
  final http.Client _httpClient;

  SupabasePortalDisputeGateway(
    SupabaseClient client, {
    @visibleForTesting EdgeFunctionInvoker? invoker,
    @visibleForTesting http.Client? httpClient,
  }) : _client = client,
       _invoke =
           invoker ??
           ((name, {body}) => client.functions.invoke(name, body: body)),
       _httpClient = httpClient ?? http.Client();

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
      requestRes = await _invoke(
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
    } on FunctionException catch (e) {
      // invoke() throws on every non-2xx. 5xx (incl. 503) is transient infra →
      // retry; any 4xx is a business rejection (opaque 404 / validation) and is
      // NEVER retried (INV-26: anti-oracle parity preserved).
      throw _classifyInvokeFailure(e);
    } catch (_) {
      // Genuine transport failure (socket reset, no HTTP status) → retryable.
      throw const PortalDisputeException(
        'Falha temporária de comunicação. Tente novamente.',
        retryable: true,
      );
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
      try {
        final uri = Uri.parse(signedUrl);
        final uploadToken = uri.queryParameters['token'];
        if (uploadToken == null) {
          throw const PortalDisputeException('URL de upload inválida.');
        }

        // To upload a file to a Storage signed URL while satisfying the bucket's
        // MIME allow-list (INV-9), we MUST send the `content-type` header.
        // The Dart Supabase SDK's `uploadBinaryToSignedUrl` lacks this capability.
        // We use a manual HTTP PUT, injecting the Supabase global headers (apikey)
        // to pass Kong's CORS preflight requirements.
        //
        // [DEV] The Edge Function mints the signedUrl using its internal SUPABASE_URL
        // (http://kong:8000). To avoid net::ERR_NAME_NOT_RESOLVED in the browser,
        // we override the scheme/host/port using the frontend's configured REST URL.
        final clientUri = Uri.parse(_client.rest.url);
        final targetUri = uri.replace(
          scheme: clientUri.scheme,
          host: clientUri.host,
          port: clientUri.port,
        );

        final headers = Map<String, String>.from(_client.rest.headers);
        headers['content-type'] = file.mimeType;
        headers['x-upsert'] = 'false';

        final putRes = await _httpClient.put(
          targetUri,
          headers: headers,
          body: file.bytes,
        );

        if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
          throw PortalDisputeException(
            'Falha no envio do arquivo: (HTTP ${putRes.statusCode})',
            retryable: putRes.statusCode >= 500,
          );
        }
      } catch (e) {
        if (e is PortalDisputeException) rethrow;
        throw const PortalDisputeException(
          'Falha no envio do arquivo. Tente novamente.',
          retryable: true,
        );
      }
    }

    // ── Phase 2: finalize (server-side magic-byte + SHA-256 verification) ─────
    try {
      await _invoke(
        'portal-finalize-upload',
        body: {'token': token, 'submissionId': submissionId},
      );
    } on FunctionException catch (e) {
      // 5xx → retryable infra. A 404 means the submission was already promoted
      // to PENDING_AUDIT on a prior attempt (finalize is idempotent) — that is a
      // success, NOT a rejection. Other 4xx carry the verification verdict.
      if (e.status >= 500) {
        throw const PortalDisputeException(
          'Serviço temporariamente indisponível. Tentando novamente…',
          retryable: true,
        );
      }
      if (e.status == 404) return PortalSubmissionOutcome.pendingAudit;
      final msg = _errorMessage(e.details).toLowerCase();
      if (msg.contains('hash')) return PortalSubmissionOutcome.hashMismatch;
      if (msg.contains('type') || msg.contains('mime')) {
        return PortalSubmissionOutcome.mimeMismatch;
      }
      return PortalSubmissionOutcome.rejected;
    } catch (_) {
      throw const PortalDisputeException(
        'Falha temporária de comunicação. Tente novamente.',
        retryable: true,
      );
    }
    // A 2xx finalize is the verified, promoted-to-audit success.
    return PortalSubmissionOutcome.pendingAudit;
  }

  /// Maps a phase-1 [FunctionException] to a typed portal failure. 5xx → retry;
  /// 4xx → opaque non-retryable (INV-26).
  PortalDisputeException _classifyInvokeFailure(FunctionException e) {
    if (e.status >= 500) {
      return const PortalDisputeException(
        'Serviço temporariamente indisponível. Tentando novamente…',
        retryable: true,
      );
    }
    return const PortalDisputeException('Envio recusado. Verifique os dados.');
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
