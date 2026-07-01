import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/webhooks/i_webhook_repository.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

class MockWebhookRepository extends Mock implements IWebhookRepository {}

void main() {
  late MockWebhookRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockWebhookRepository();
    container = ProviderContainer(
      overrides: [webhookRepositoryProvider.overrideWithValue(mockRepo)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('Webhook Providers Tests', () {
    test('webhookRepositoryProvider returns mocked repo', () {
      final repo = container.read(webhookRepositoryProvider);
      expect(repo, isA<MockWebhookRepository>());
    });

    test('webhookEndpointHealthProvider fetches endpoints', () async {
      final endpoints = [
        WebhookEndpointView(
          id: 'ep-123',
          url: 'https://test.com',
          isActive: true,
          createdAt: DateTime.parse('2026-07-01T12:00:00Z'),
          totalLogs: 0,
          pendingCount: 0,
          deliveringCount: 0,
          successCount: 0,
          failedCount: 0,
          deadCount: 0,
        ),
      ];

      when(
        () => mockRepo.findEndpointHealth(),
      ).thenAnswer((_) async => endpoints);

      final state = await container.read(webhookEndpointHealthProvider.future);
      expect(state.length, 1);
      expect(state.first.id, 'ep-123');
    });

    test('selectedEndpointIdProvider mutates state', () {
      expect(container.read(selectedEndpointIdProvider), isNull);

      container.read(selectedEndpointIdProvider.notifier).select('ep-123');
      expect(container.read(selectedEndpointIdProvider), 'ep-123');
    });

    test('webhookSecretRevealProvider sets and scrubs secret', () {
      final notifier = container.read(webhookSecretRevealProvider.notifier);

      notifier.setRevealed('ABCDEF', 1);
      expect(container.read(webhookSecretRevealProvider).secretHex, 'ABCDEF');

      notifier.scrub();
      expect(container.read(webhookSecretRevealProvider).secretHex, isNull);
    });
  });
}
