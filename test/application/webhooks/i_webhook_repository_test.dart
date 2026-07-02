import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/i_webhook_repository.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/application/webhooks/webhook_secret_reveal_result.dart';

class DummyWebhookRepository implements IWebhookRepository {
  @override
  Future<WebhookSecretRevealResult> revealSecret(String endpointId) async {
    return const WebhookSecretRevealResult(secretHex: 'dummy', version: 1);
  }

  @override
  Future<WebhookSecretRevealResult> rotateSecret(String endpointId) async {
    return const WebhookSecretRevealResult(
      secretHex: 'dummy-rotated',
      version: 2,
    );
  }

  @override
  Future<void> createEndpoint(String orgId, String url) async {}

  @override
  Future<List<WebhookEndpointView>> findEndpointHealth() async {
    return [];
  }

  @override
  Stream<List<WebhookDeliveryLogView>> watchDeliveryLogs(String endpointId) {
    return const Stream.empty();
  }

  @override
  Future<void> manualReplay(String logId) async {}
}

void main() {
  group('IWebhookRepository Test', () {
    test('compiles and can be implemented', () {
      final repo = DummyWebhookRepository();
      expect(repo, isA<IWebhookRepository>());
    });
  });
}
