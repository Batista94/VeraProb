import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';

void main() {
  group('WebhookDeliveryLogView Test', () {
    test('fromMap serializes correctly', () {
      final data = {
        'id': 'log-123',
        'endpoint_id': 'ep-123',
        'event_type': 'invoice.paid',
        'payload': {'key': 'value'},
        'status': 'SUCCESS',
        'attempt_count': 1,
        'created_at': '2026-07-01T12:00:00Z',
        'ledger_entry_id': 'ledg-456',
      };

      final logView = WebhookDeliveryLogView.fromMap(data);

      expect(logView.id, 'log-123');
      expect(logView.endpointId, 'ep-123');
      expect(logView.eventType, 'invoice.paid');
      expect(logView.status, WebhookDeliveryStatusView.success);
      expect(logView.attemptCount, 1);
      expect(logView.createdAt, DateTime.parse('2026-07-01T12:00:00Z'));
      expect(logView.payload['key'], 'value');
      expect(logView.ledgerEntryId, 'ledg-456');
    });
  });
}
