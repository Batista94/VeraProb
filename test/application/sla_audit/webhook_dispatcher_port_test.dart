import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/webhook_dispatcher_port.dart';

class MockWebhookDispatcherPort implements IWebhookDispatcherPort {
  @override
  Future<void> dispatchVerdictWebhooks({required String organizationId}) async {}
}

void main() {
  group('IWebhookDispatcherPort Tests', () {
    test('Can instantiate and call mock', () async {
      final port = MockWebhookDispatcherPort();
      await port.dispatchVerdictWebhooks(organizationId: 'org1');
      expect(port, isNotNull);
    });
  });
}
