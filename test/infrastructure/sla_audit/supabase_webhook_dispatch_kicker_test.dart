import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/infrastructure/sla_audit/supabase_webhook_dispatch_kicker.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  group('SupabaseWebhookDispatchKicker', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockFunctionsClient mockFunctionsClient;
    late SupabaseWebhookDispatchKicker kicker;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockFunctionsClient = MockFunctionsClient();
      when(() => mockSupabaseClient.functions).thenReturn(mockFunctionsClient);
      kicker = SupabaseWebhookDispatchKicker(mockSupabaseClient);
    });

    test(
      'should invoke dispatch-verdict-webhooks with organizationId',
      () async {
        when(
          () => mockFunctionsClient.invoke(
            'dispatch-verdict-webhooks',
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => FunctionResponse(data: null, status: 200));

        await kicker.dispatchVerdictWebhooks(organizationId: 'org-123');

        verify(
          () => mockFunctionsClient.invoke(
            'dispatch-verdict-webhooks',
            body: {'organization_id': 'org-123'},
          ),
        ).called(1);
      },
    );

    test('should fail silently if functions client throws exception', () async {
      when(
        () => mockFunctionsClient.invoke(
          'dispatch-verdict-webhooks',
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('Network error'));

      // Should not throw
      await kicker.dispatchVerdictWebhooks(organizationId: 'org-123');
    });
  });
}
