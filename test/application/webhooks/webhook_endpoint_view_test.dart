import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';

void main() {
  group('WebhookEndpointView Test', () {
    test('fromMap serializes correctly', () {
      final data = {
        'id': 'ep-123',
        'url': 'https://example.com/hook',
        'is_active': true,
        'created_at': '2026-07-01T12:00:00Z',
        'last_dispatched_at': '2026-07-01T12:05:00Z',
        'total_logs': 12,
        'pending_count': 0,
        'delivering_count': 0,
        'success_count': 10,
        'failed_count': 2,
        'dead_count': 0,
      };

      final endpoint = WebhookEndpointView.fromMap(data);

      expect(endpoint.id, 'ep-123');
      expect(endpoint.url, 'https://example.com/hook');
      expect(endpoint.isActive, isTrue);
      expect(endpoint.createdAt, DateTime.parse('2026-07-01T12:00:00Z'));
      expect(endpoint.lastDispatchedAt, DateTime.parse('2026-07-01T12:05:00Z'));
      expect(endpoint.successCount, 10);
      expect(endpoint.failedCount, 2);
    });
  });
}
