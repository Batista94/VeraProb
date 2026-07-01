import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';

void main() {
  group('WebhookDeliveryStatusView Test', () {
    test('fromString parses correctly', () {
      expect(
        WebhookDeliveryStatusView.fromString('SUCCESS'),
        WebhookDeliveryStatusView.success,
      );
      expect(
        WebhookDeliveryStatusView.fromString('FAILED'),
        WebhookDeliveryStatusView.failed,
      );
      expect(
        WebhookDeliveryStatusView.fromString('PENDING'),
        WebhookDeliveryStatusView.pending,
      );
      expect(
        WebhookDeliveryStatusView.fromString('DELIVERING'),
        WebhookDeliveryStatusView.delivering,
      );
      expect(
        WebhookDeliveryStatusView.fromString('DEAD'),
        WebhookDeliveryStatusView.dead,
      );

      // Fallback para pending se for desconhecido
      expect(
        WebhookDeliveryStatusView.fromString('UNKNOWN_STATUS'),
        WebhookDeliveryStatusView.pending,
      );
    });
  });
}
