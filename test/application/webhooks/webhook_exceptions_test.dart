import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_exceptions.dart';

void main() {
  group('Webhook Exceptions Test', () {
    test('WebhookApplicationException retains its message', () {
      const ex = WebhookApplicationException('Erro teste');
      expect(ex.message, 'Erro teste');
      expect(ex.toString(), 'Erro teste');
    });
  });
}
