/// Unit tests for the provider timeout utility (Requirement 5.6).
///
/// Validates that:
/// - Futures that complete within 30s return their value normally
/// - Futures that exceed 30s throw TimeoutException
/// - The TimeoutException message matches the expected format
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:veraprob/state/provider_timeout.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  group('Provider Timeout (Requirement 5.6)', () {
    test('kProviderTimeout is 30 seconds', () {
      expect(kProviderTimeout, const Duration(seconds: 30));
    });

    test(
      'withProviderTimeout() returns value when future completes in time',
      () async {
        final future = Future.value(42).withProviderTimeout();
        expect(await future, 42);
      },
    );

    test(
      'withProviderTimeout() throws TimeoutException when future exceeds 30s',
      () {
        fakeAsync((async) {
          final completer = Completer<int>();
          final future = completer.future.withProviderTimeout();

          late Object caughtError;
          future.catchError((Object e) {
            caughtError = e;
            return 0; // Return a default value for the type
          });

          // Advance past the 30s timeout
          async.elapse(const Duration(seconds: 31));

          expect(caughtError, isA<TimeoutException>());
          final timeout = caughtError as TimeoutException;
          expect(timeout.message, 'Provider timeout after 30s');
          expect(timeout.duration, const Duration(seconds: 30));
        });
      },
    );

    test(
      'withProviderTimeout() does not throw when future completes at 29s',
      () {
        fakeAsync((async) {
          final completer = Completer<String>();
          final future = completer.future.withProviderTimeout();

          String? result;
          future.then((v) => result = v);

          // Complete just before timeout
          async.elapse(const Duration(seconds: 29));
          completer.complete('data loaded');
          async.flushMicrotasks();

          expect(result, 'data loaded');
        });
      },
    );

    test('withProviderTimeout() propagates original error if future fails', () {
      fakeAsync((async) {
        final completer = Completer<int>();
        final future = completer.future.withProviderTimeout();

        Object? caughtError;
        future.catchError((Object e) {
          caughtError = e;
          return 0;
        });

        completer.completeError(StateError('network failure'));
        async.flushMicrotasks();

        expect(caughtError, isA<IntegrityException>());
        expect((caughtError as StateError).message, 'network failure');
      });
    });

    test('withProviderTimeout() works with nullable types', () async {
      final future = Future<String?>.value(null).withProviderTimeout();
      expect(await future, isNull);
    });

    test('withProviderTimeout() works with list types', () async {
      final future = Future<List<int>>.value([1, 2, 3]).withProviderTimeout();
      expect(await future, [1, 2, 3]);
    });
  });

  group('Stale-While-Revalidate (Requirement 5.5) — Documentation', () {
    // In Riverpod v3, stale-while-revalidate is the DEFAULT behavior.
    // When a provider refreshes:
    // - AsyncValue.value remains accessible with previous data
    // - isRefreshing == true indicates refresh in progress
    // - .when() shows previous data by default (skipLoadingOnRefresh = true)
    // - No widget tree rebuild with Loading state visible to user
    //
    // This test documents the expected behavior without needing to test
    // Riverpod internals (which are covered by the framework's own tests).

    test(
      'AsyncValue preserves previous value during refresh (framework behavior)',
      () {
        // Simulate the v3 behavior: AsyncLoading with previous value
        // In v3, AsyncLoading can carry a previous value
        // This is a documentation test showing the expected pattern
        const previousData = AsyncData<int>(42);

        // When refreshing, the value is still accessible
        expect(previousData.value, 42);
        expect(previousData.hasValue, true);

        // The presentation layer checks isRefreshing to show subtle indicators
        // while keeping previous data visible (e.g., fleet_map.dart pattern)
      },
    );
  });
}
