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
import 'package:veraprob/application/webhooks/webhook_secret_reveal_result.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Exceção de domínio tipada para operações de secret de webhook.
///
/// INV-10: nunca exposta como Exception/StateError na camada de aplicação.
class WebhookSecretException extends DomainException {
  const WebhookSecretException(super.message);
}

/// Implementação Supabase do IWebhookRepository (P1: revealSecret + rotateSecret).
class SupabaseWebhookRepository implements IWebhookRepository {
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
        throw const WebhookSecretException(
          'Resposta inválida da função de provisionamento.',
        );
      }

      final secretHex = data['secret_hex'] as String?;
      final version = data['version'] as int?;

      if (secretHex == null || secretHex.isEmpty || version == null) {
        throw const WebhookSecretException(
          'Dados do segredo ausentes ou inválidos.',
        );
      }

      return WebhookSecretRevealResult(secretHex: secretHex, version: version);
    } on WebhookSecretException {
      rethrow;
    } on FunctionException catch (e) {
      // INV-26 parity: edge fn retornou 404 (org errada, role errado).
      // Mapeia para mensagem de domínio sem vazar detalhes.
      if (e.status == 404) {
        throw const WebhookSecretException(
          'Acesso negado ou organização inválida.',
        );
      }
      throw WebhookSecretException(
        'Falha ao contatar o serviço de provisionamento (HTTP ${e.status}).',
      );
    } on Object {
      throw const WebhookSecretException(
        'Serviço de provisionamento indisponível. Tente novamente.',
      );
    }
  }
}
