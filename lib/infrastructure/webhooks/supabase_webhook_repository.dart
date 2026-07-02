// SupabaseWebhookRepository — Infrastructure implementation (P1).
//
// INV-13: features/ nunca importam este arquivo. Acessam apenas IWebhookRepository
// via webhookRepositoryProvider (lib/state/providers/webhook_providers.dart).
//
// INV-10: nenhum throw Exception/StateError/FormatException.
//         Todos os erros mapeados para WebhookSecretException (DomainException).
// INV-31: secretHex é material derivado recomputado na edge fn. Nunca persistido.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/webhooks/i_webhook_repository.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/application/webhooks/webhook_exceptions.dart';
import 'package:veraprob/application/webhooks/webhook_secret_reveal_result.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Exceção de domínio tipada para operações de secret de webhook.
///
/// INV-10: nunca exposta como Exception/StateError na camada de aplicação.
class WebhookSecretException extends DomainException {
  const WebhookSecretException(super.message);
}

/// Implementação Supabase do IWebhookRepository.
class SupabaseWebhookRepository
    with PostgresErrorInterceptor
    implements IWebhookRepository {
  final SupabaseClient _client;

  const SupabaseWebhookRepository(this._client);

  @override
  Future<WebhookSecretRevealResult> revealSecret(String orgId) {
    return _invokeReveal(orgId, 'provision');
  }

  @override
  Future<WebhookSecretRevealResult> rotateSecret(String orgId) {
    return _invokeReveal(orgId, 'rotate');
  }

  @override
  Future<void> createEndpoint(String orgId, String url) async {
    try {
      await _client.from('webhook_endpoints').insert(<String, dynamic>{
        'organization_id': orgId,
        'url': url,
      });
    } on PostgrestException catch (e) {
      throw _mapCreateEndpointException(e);
    } catch (_) {
      throw const WebhookApplicationException(
        'Não foi possível criar o endpoint. Tente novamente.',
      );
    }
  }

  /// 23514 = CHECK (url LIKE 'https://%'). INV-26: RLS/not-found → genérico.
  WebhookApplicationException _mapCreateEndpointException(
    PostgrestException e,
  ) {
    return switch (e.code) {
      '23514' => const WebhookApplicationException(
        'URL inválida. O endpoint deve usar HTTPS.',
      ),
      _ => const WebhookApplicationException(
        'Não foi possível criar o endpoint. Verifique os dados e tente novamente.',
      ),
    };
  }

  @override
  Future<List<WebhookEndpointView>> findEndpointHealth() async {
    try {
      final response = await _client.from('v_webhook_endpoint_health').select();
      final data = response as List<dynamic>;
      return data
          .map((e) => WebhookEndpointView.fromMap(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'webhook_endpoint');
    } catch (_) {
      throw const WebhookSecretException(
        'Falha ao consultar os endpoints de webhook.',
      );
    }
  }

  @override
  Stream<List<WebhookDeliveryLogView>> watchDeliveryLogs(String endpointId) {
    return _client
        .from('webhook_delivery_logs')
        .stream(primaryKey: ['id'])
        .eq('endpoint_id', endpointId)
        .order('created_at', ascending: false)
        .map(
          (data) => data.map((e) => WebhookDeliveryLogView.fromMap(e)).toList(),
        );
  }

  @override
  Future<void> manualReplay(String logId) async {
    try {
      await _client.rpc('webhook_manual_replay', params: {'p_log_id': logId});
    } on PostgrestException catch (e) {
      throw _mapReplayException(e);
    } catch (_) {
      throw const WebhookApplicationException(
        'Não foi possível solicitar o reprocessamento. Tente novamente.',
      );
    }
  }

  /// Traduz o erro da RPC para vocabulário de domínio (PT), pronto para a UI.
  ///
  /// P0001 = regra de negócio (status inválido / rate limit): a própria RPC já
  /// emite a mensagem em português. INV-26: not-found (P0002) e RLS (42501)
  /// recebem mensagem genérica — sem oráculo de existência/pertencimento.
  WebhookApplicationException _mapReplayException(PostgrestException e) {
    return switch (e.code) {
      'P0001' => WebhookApplicationException(e.message),
      _ => const WebhookApplicationException(
        'Log de entrega indisponível para reprocessamento.',
      ),
    };
  }

  // ── Private ──────────────────────────────────────────────────────────────

  Future<WebhookSecretRevealResult> _invokeReveal(
    String orgId,
    String action,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'reveal-webhook-signing-secret',
        body: <String, dynamic>{'action': action},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        throw const WebhookApplicationException(
          'Resposta inválida da função de provisionamento.',
        );
      }

      final secretHex = data['secret_hex'] as String?;
      final version = data['version'] as int?;

      if (secretHex == null || secretHex.isEmpty || version == null) {
        throw const WebhookApplicationException(
          'Dados do segredo ausentes ou inválidos.',
        );
      }

      return WebhookSecretRevealResult(secretHex: secretHex, version: version);
    } on WebhookApplicationException {
      rethrow;
    } on FunctionException catch (e) {
      // Reveal-once estrito: 409 = chave ativa já provisionada.
      if (e.status == 409) {
        throw const WebhookApplicationException(
          'O segredo desta organização já foi provisionado e não pode ser '
          'exibido novamente. Utilize a rotação para gerar uma nova chave.',
        );
      }
      // INV-26 parity: edge fn retornou 404 (org errada, role errado).
      // Mapeia para mensagem de domínio sem vazar detalhes.
      if (e.status == 404) {
        throw const WebhookApplicationException(
          'Acesso negado ou organização inválida.',
        );
      }
      throw WebhookApplicationException(
        'Falha ao contatar o serviço de provisionamento (HTTP ${e.status}).',
      );
    } on Object {
      throw const WebhookApplicationException(
        'Serviço de provisionamento indisponível. Tente novamente.',
      );
    }
  }
}
