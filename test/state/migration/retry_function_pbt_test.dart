/// **Validates: Requirements 7.1, 7.2, 7.3, 7.4**
///
/// Property 8: Retry Function Correctness
///
/// For any (retryCount, error) pair passed to the global retry function:
/// - If error is a ProviderException, the function SHALL return null (no retry).
/// - If error is an HttpException with status code in {400, 401, 403, 404, 409, 422},
///   the function SHALL return null.
/// - If retryCount > 5, the function SHALL return null.
/// - Otherwise, the function SHALL return a Duration equal to
///   min(200ms × 2^retryCount, 6400ms) ± 10% jitter.
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll, setUp, tearDown;

import 'package:veraprob/state/retry_policy.dart';

/// Obtains a real [ProviderException] from the framework by triggering
/// a provider dependency failure. This avoids using the @internal constructor.
ProviderException _obtainRealProviderException() {
  final failingProvider = Provider<int>((ref) => throw Exception('dep fail'));
  final dependentProvider = FutureProvider<int>((ref) async {
    return ref.watch(failingProvider);
  });

  final container = ProviderContainer.test();
  // Reading the dependent provider will wrap the error in ProviderException
  try {
    final sub = container.listen(dependentProvider.future, (_, _) {});
    sub.read();
  } on ProviderException catch (e) {
    container.dispose();
    return e;
  } catch (_) {
    // fallback: try reading directly
  }
  container.dispose();
  // If we can't get one from the framework, we'll skip the ProviderException tests
  throw StateError('Could not obtain ProviderException from framework');
}

// Feature: riverpod-v3-migration, Property 8: Retry Function Correctness
void main() {
  group('Property 8: Retry Function Correctness', () {
    late ProviderException realProviderException;

    setUpAll(() {
      try {
        realProviderException = _obtainRealProviderException();
      } catch (_) {
        // If we can't obtain one, tests using it will be skipped
        realProviderException = _obtainRealProviderExceptionFallback();
      }
    });

    // ── Branch 1: ProviderException always returns null ──────────────────
    Glados(any.int).test(
      'returns null for any ProviderException regardless of retryCount',
      (retryCount) {
        final result = classifyForRetry(
          retryCount.abs() % 10,
          realProviderException,
        );
        expect(result, isNull);
      },
    );

    // ── Branch 2: Non-recoverable HTTP status codes return null ──────────
    Glados2(any.int, any.choose([400, 401, 403, 404, 409, 422])).test(
      'returns null for HttpException with non-recoverable status codes',
      (retryCount, statusCode) {
        final error = HttpException(statusCode);
        final result = classifyForRetry(retryCount.abs() % 6, error);
        expect(result, isNull);
      },
    );

    // ── Branch 3: retryCount > 5 returns null ───────────────────────────
    Glados(any.intInRange(6, 100)).test('returns null when retryCount > 5', (
      retryCount,
    ) {
      final error = Exception('network timeout');
      final result = classifyForRetry(retryCount, error);
      expect(result, isNull);
    });

    // ── Branch 4: Recoverable errors with valid retryCount return Duration ─
    Glados2(any.intInRange(0, 5), any.choose([500, 502, 503, 504])).test(
      'returns Duration with correct backoff for recoverable HTTP errors',
      (retryCount, statusCode) {
        final error = HttpException(statusCode);
        final result = classifyForRetry(retryCount, error);

        expect(result, isNotNull);

        final expectedBase = min(200 * pow(2, retryCount), 6400).toInt();
        // ±10% jitter tolerance
        expect(
          result!.inMilliseconds,
          closeTo(expectedBase, expectedBase * 0.1),
        );
      },
    );

    // ── Branch 4b: Generic exceptions with valid retryCount return Duration ─
    Glados(any.intInRange(0, 5)).test(
      'returns Duration with correct backoff for generic exceptions',
      (retryCount) {
        final error = Exception('network error');
        final result = classifyForRetry(retryCount, error);

        expect(result, isNotNull);

        final expectedBase = min(200 * pow(2, retryCount), 6400).toInt();
        // ±10% jitter tolerance
        expect(
          result!.inMilliseconds,
          closeTo(expectedBase, expectedBase * 0.1),
        );
      },
    );

    // ── Combined property: exhaustive classification ─────────────────────
    Glados2(
      any.int,
      any.choose([
        Exception('network'),
        const HttpException(500),
        const HttpException(400),
        const HttpException(401),
        const HttpException(403),
        const HttpException(404),
        const HttpException(409),
        const HttpException(422),
        const HttpException(502),
        const HttpException(503),
      ]),
    ).test(
      'returns correct duration or null for any (retryCount, error) pair',
      (retryCount, error) {
        final count = retryCount.abs() % 10;
        final result = classifyForRetry(count, error);

        if (error is HttpException &&
            [400, 401, 403, 404, 409, 422].contains(error.statusCode)) {
          expect(
            result,
            isNull,
            reason: 'Non-recoverable HTTP ${error.statusCode} must not retry',
          );
        } else if (count > 5) {
          expect(result, isNull, reason: 'retryCount > 5 must not retry');
        } else {
          expect(
            result,
            isNotNull,
            reason: 'Recoverable error with count=$count should retry',
          );
          final expectedBase = min(200 * pow(2, count), 6400).toInt();
          expect(
            result!.inMilliseconds,
            closeTo(expectedBase, expectedBase * 0.1),
            reason: 'Backoff should be ~${expectedBase}ms for count=$count',
          );
        }
      },
    );

    // ── ProviderException combined test ──────────────────────────────────
    Glados(any.intInRange(0, 10)).test(
      'ProviderException always returns null regardless of retryCount',
      (retryCount) {
        final result = classifyForRetry(retryCount, realProviderException);
        expect(result, isNull, reason: 'ProviderException must not retry');
      },
    );
  });
}

/// Fallback: obtain ProviderException by reading a failing provider's future.
ProviderException _obtainRealProviderExceptionFallback() {
  final failingProvider = Provider<int>((ref) => throw Exception('dep'));
  final container = ProviderContainer.test();
  try {
    container.read(failingProvider);
  } on ProviderException catch (e) {
    container.dispose();
    return e;
  } catch (_) {
    // ignore
  }
  container.dispose();
  throw StateError('Could not obtain ProviderException');
}
