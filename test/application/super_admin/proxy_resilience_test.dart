import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/super_admin/proxy_resilience_notifier.dart';

void main() {
  ProviderContainer createContainer({
    Duration cooldown = Duration.zero,
    int threshold = 3,
  }) {
    return ProviderContainer(
      overrides: [
        proxyResilienceCooldownProvider.overrideWithValue(cooldown),
        proxyResilienceThresholdProvider.overrideWithValue(threshold),
      ],
    );
  }

  group('ProxyResilienceNotifier', () {
    group('Happy Path', () {
      test('starts in healthy state', () {
        final container = createContainer();
        addTearDown(container.dispose);

        final state = container.read(proxyResilienceProvider);
        expect(state.status, ResilienceStatus.healthy);
        expect(state.canWrite, isTrue);
        expect(state.isStale, isFalse);
        expect(state.consecutiveFailures, 0);
      });

      test('recordSuccess keeps healthy state', () {
        final container = createContainer();
        addTearDown(container.dispose);

        container.read(proxyResilienceProvider.notifier).recordSuccess();
        expect(
          container.read(proxyResilienceProvider).status,
          ResilienceStatus.healthy,
        );
      });
    });

    group('Proxy Crash (500) — Degraded Mode', () {
      test('single failure transitions to degraded', () {
        final container = createContainer();
        addTearDown(container.dispose);

        container.read(proxyResilienceProvider.notifier).recordFailure();

        final state = container.read(proxyResilienceProvider);
        expect(state.status, ResilienceStatus.degraded);
        expect(state.consecutiveFailures, 1);
        expect(state.isStale, isTrue);
        expect(state.canWrite, isFalse);
      });

      test('recordSuccess after failure resets to healthy', () {
        final container = createContainer();
        addTearDown(container.dispose);

        final notifier = container.read(proxyResilienceProvider.notifier);
        notifier.recordFailure();
        notifier.recordFailure();
        notifier.recordSuccess();

        final state = container.read(proxyResilienceProvider);
        expect(state.status, ResilienceStatus.healthy);
        expect(state.consecutiveFailures, 0);
        expect(state.canWrite, isTrue);
      });
    });

    group('Circuit Breaker — Unavailable', () {
      test('3 consecutive failures opens circuit (unavailable)', () {
        final container = createContainer();
        addTearDown(container.dispose);

        final notifier = container.read(proxyResilienceProvider.notifier);
        notifier.recordFailure(); // 1 → degraded
        notifier.recordFailure(); // 2 → degraded
        notifier.recordFailure(); // 3 → unavailable

        final state = container.read(proxyResilienceProvider);
        expect(state.status, ResilienceStatus.unavailable);
        expect(state.consecutiveFailures, 3);
        expect(state.canWrite, isFalse);
      });

      test('custom threshold respected', () {
        final container = createContainer(threshold: 5);
        addTearDown(container.dispose);

        final notifier = container.read(proxyResilienceProvider.notifier);
        for (var i = 0; i < 4; i++) {
          notifier.recordFailure();
        }
        expect(
          container.read(proxyResilienceProvider).status,
          ResilienceStatus.degraded,
        );

        notifier.recordFailure(); // 5th → unavailable
        expect(
          container.read(proxyResilienceProvider).status,
          ResilienceStatus.unavailable,
        );
      });

      test('cooldown transitions from unavailable to degraded', () {
        fakeAsync((async) {
          final container = createContainer(
            cooldown: const Duration(seconds: 30),
          );
          addTearDown(container.dispose);

          final notifier = container.read(proxyResilienceProvider.notifier);
          notifier.recordFailure();
          notifier.recordFailure();
          notifier.recordFailure();
          expect(
            container.read(proxyResilienceProvider).status,
            ResilienceStatus.unavailable,
          );

          // Before cooldown expires
          async.elapse(const Duration(seconds: 29));
          expect(
            container.read(proxyResilienceProvider).status,
            ResilienceStatus.unavailable,
          );

          // After cooldown expires → allows retry (degraded)
          async.elapse(const Duration(seconds: 1));
          expect(
            container.read(proxyResilienceProvider).status,
            ResilienceStatus.degraded,
          );
        });
      });
    });

    group('Write Protection (Integrity)', () {
      test('canWrite is false in degraded state', () {
        final container = createContainer();
        addTearDown(container.dispose);

        container.read(proxyResilienceProvider.notifier).recordFailure();
        expect(container.read(proxyResilienceProvider).canWrite, isFalse);
      });

      test('canWrite is false in unavailable state', () {
        final container = createContainer();
        addTearDown(container.dispose);

        final notifier = container.read(proxyResilienceProvider.notifier);
        notifier.recordFailure();
        notifier.recordFailure();
        notifier.recordFailure();
        expect(container.read(proxyResilienceProvider).canWrite, isFalse);
      });

      test('canWrite is true only when healthy', () {
        final container = createContainer();
        addTearDown(container.dispose);

        expect(container.read(proxyResilienceProvider).canWrite, isTrue);
      });
    });

    group('Confidentiality — Reset on Logout (INV-22)', () {
      test('reset clears all state back to healthy', () {
        final container = createContainer();
        addTearDown(container.dispose);

        final notifier = container.read(proxyResilienceProvider.notifier);
        notifier.recordFailure();
        notifier.recordFailure();
        notifier.recordFailure();
        expect(
          container.read(proxyResilienceProvider).status,
          ResilienceStatus.unavailable,
        );

        notifier.reset();

        final state = container.read(proxyResilienceProvider);
        expect(state.status, ResilienceStatus.healthy);
        expect(state.consecutiveFailures, 0);
        expect(state.canWrite, isTrue);
        expect(state.isStale, isFalse);
      });

      test('reset cancels active cooldown timer', () {
        fakeAsync((async) {
          final container = createContainer(
            cooldown: const Duration(seconds: 30),
          );
          addTearDown(container.dispose);

          final notifier = container.read(proxyResilienceProvider.notifier);
          notifier.recordFailure();
          notifier.recordFailure();
          notifier.recordFailure();

          // Reset before cooldown fires
          notifier.reset();
          expect(
            container.read(proxyResilienceProvider).status,
            ResilienceStatus.healthy,
          );

          // Elapse past cooldown — should NOT change state
          async.elapse(const Duration(seconds: 60));
          expect(
            container.read(proxyResilienceProvider).status,
            ResilienceStatus.healthy,
          );
        });
      });
    });

    group('Edge Cases', () {
      test('recordSuccess during cooldown resets fully', () {
        fakeAsync((async) {
          final container = createContainer(
            cooldown: const Duration(seconds: 30),
          );
          addTearDown(container.dispose);

          final notifier = container.read(proxyResilienceProvider.notifier);
          notifier.recordFailure();
          notifier.recordFailure();
          notifier.recordFailure();

          async.elapse(const Duration(seconds: 10));
          notifier.recordSuccess();

          expect(
            container.read(proxyResilienceProvider).status,
            ResilienceStatus.healthy,
          );

          // Cooldown timer should be cancelled
          async.elapse(const Duration(seconds: 30));
          expect(
            container.read(proxyResilienceProvider).status,
            ResilienceStatus.healthy,
          );
        });
      });

      test('container dispose does not throw with active timer', () {
        fakeAsync((async) {
          final container = createContainer(
            cooldown: const Duration(seconds: 30),
          );

          final notifier = container.read(proxyResilienceProvider.notifier);
          notifier.recordFailure();
          notifier.recordFailure();
          notifier.recordFailure();

          // Dispose while cooldown timer is active
          container.dispose();

          // Elapse — no pending timers should fire
          async.elapse(const Duration(seconds: 60));
        });
      });
    });
  });
}
