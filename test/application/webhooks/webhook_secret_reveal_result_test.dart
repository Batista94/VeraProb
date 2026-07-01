import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_secret_reveal_result.dart';

void main() {
  group('WebhookSecretRevealResult Test', () {
    test('can be instantiated', () {
      const result = WebhookSecretRevealResult(
        secretHex: 'whsec_abc123',
        version: 1,
      );
      expect(result.secretHex, 'whsec_abc123');
      expect(result.version, 1);
    });
  });
}
