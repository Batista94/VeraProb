// IWebhookRepository — Application port (P1 scope).
//
// INV-13: features/ NUNCA importa lib/infrastructure/. Features lêem apenas
// os ViewModels/DTOs de lib/application/. A implementação concreta
// (SupabaseWebhookRepository) fica em lib/infrastructure/webhooks/.
//
// P1: apenas operações de provisioning/rotação de segredo.
// P2 expandirá com findEndpointHealth, watchDeliveryLogs, etc.

import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/application/webhooks/webhook_secret_reveal_result.dart';

abstract class IWebhookRepository {
  /// Provisiona (cria idempotente) ou exibe uma única vez o segredo ativo da org.
  ///
  /// Mapeia para action = 'provision' na edge fn reveal-webhook-signing-secret.
  /// INV-31: retorna material hex recomputado em runtime. Nada persiste no DB.
  Future<WebhookSecretRevealResult> revealSecret(String orgId);

  /// Rotaciona o segredo: active → retiring + nova active (version+1).
  ///
  /// Mapeia para action = 'rotate' na edge fn reveal-webhook-signing-secret.
  Future<WebhookSecretRevealResult> rotateSecret(String orgId);

  Future<List<WebhookEndpointView>> findEndpointHealth();

  Stream<List<WebhookDeliveryLogView>> watchDeliveryLogs(String endpointId);

  Future<void> manualReplay(String logId);
}
