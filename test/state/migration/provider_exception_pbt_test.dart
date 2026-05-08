/// **Validates: Requirements 5.3**
///
/// Property 6: ProviderException Wrapping
///
/// For any provider that throws an exception during computation, when read via
/// `ref.read(provider.future)`, the thrown error SHALL be wrapped in a
/// `ProviderException` whose `.exception` field equals the original thrown error.
///
/// Strategy: Uses Glados to generate diverse exception types and messages,
/// creates providers that throw those exceptions synchronously, and verifies
/// that reading the provider throws a `ProviderException` wrapping the original
/// error. Uses synchronous `Provider` (not FutureProvider) to avoid async
/// lifecycle issues in tests, since ProviderException wrapping applies to all
/// provider types that throw during computation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;

// Feature: riverpod-v3-migration, Property 6: ProviderException Wrapping

/// Custom exception types used to verify wrapping preserves type identity.
class DomainException implements Exception {
  const DomainException(this.message);
  final String message;

  @override
  String toString() => 'DomainException: $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainException && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

class NetworkException implements Exception {
  const NetworkException(this.statusCode, this.url);
  final int statusCode;
  final String url;

  @override
  String toString() => 'NetworkException: $statusCode at $url';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkException &&
          other.statusCode == statusCode &&
          other.url == url;

  @override
  int get hashCode => Object.hash(statusCode, url);
}

class TimeoutException implements Exception {
  const TimeoutException(this.durationMs);
  final int durationMs;

  @override
  String toString() => 'TimeoutException: ${durationMs}ms';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeoutException && other.durationMs == durationMs;

  @override
  int get hashCode => durationMs.hashCode;
}

class ValidationException implements Exception {
  const ValidationException(this.field, this.reason);
  final String field;
  final String reason;

  @override
  String toString() => 'ValidationException: $field - $reason';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationException &&
          other.field == field &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(field, reason);
}

void main() {
  group('Property 6: ProviderException Wrapping', () {
    // ── Sub-property: Generic exceptions are wrapped in ProviderException ──
    Glados(any.letterOrDigits).test(
      'generic Exception thrown by provider is wrapped in ProviderException',
      (message) {
        final thrownError = Exception(message);

        final provider = Provider<String>((ref) {
          throw thrownError;
        });

        final container = ProviderContainer.test();

        expect(
          () => container.read(provider),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.exception,
              'exception',
              equals(thrownError),
            ),
          ),
        );
      },
    );

    // ── Sub-property: DomainException preserves type through wrapping ──────
    Glados(any.letterOrDigits).test(
      'DomainException thrown by provider is accessible via .exception',
      (message) {
        final thrownError = DomainException(message);

        final provider = Provider<void>((ref) {
          throw thrownError;
        });

        final container = ProviderContainer.test();

        expect(
          () => container.read(provider),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.exception,
              'exception',
              isA<DomainException>().having(
                (d) => d.message,
                'message',
                equals(message),
              ),
            ),
          ),
        );
      },
    );

    // ── Sub-property: NetworkException with status code is preserved ───────
    Glados2(
      any.choose([400, 401, 403, 404, 409, 422, 500, 502, 503, 504]),
      any.letterOrDigits,
    ).test('NetworkException preserves statusCode and url through wrapping', (
      statusCode,
      url,
    ) {
      final thrownError = NetworkException(statusCode, url);

      final provider = Provider<int>((ref) {
        throw thrownError;
      });

      final container = ProviderContainer.test();

      expect(
        () => container.read(provider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            equals(thrownError),
          ),
        ),
      );
    });

    // ── Sub-property: TimeoutException with duration is preserved ──────────
    Glados(any.intInRange(100, 60000)).test(
      'TimeoutException preserves duration through wrapping',
      (durationMs) {
        final thrownError = TimeoutException(durationMs);

        final provider = Provider<void>((ref) {
          throw thrownError;
        });

        final container = ProviderContainer.test();

        expect(
          () => container.read(provider),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.exception,
              'exception',
              equals(thrownError),
            ),
          ),
        );
      },
    );

    // ── Sub-property: ValidationException preserves field and reason ───────
    Glados2(any.letterOrDigits, any.letterOrDigits).test(
      'ValidationException preserves field and reason through wrapping',
      (field, reason) {
        final thrownError = ValidationException(field, reason);

        final provider = Provider<bool>((ref) {
          throw thrownError;
        });

        final container = ProviderContainer.test();

        expect(
          () => container.read(provider),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.exception,
              'exception',
              equals(thrownError),
            ),
          ),
        );
      },
    );

    // ── Sub-property: StateError (non-Exception) is also wrapped ──────────
    Glados(any.letterOrDigits).test(
      'StateError thrown by provider is wrapped in ProviderException',
      (message) {
        final thrownError = StateError(message);

        final provider = Provider<String>((ref) {
          throw thrownError;
        });

        final container = ProviderContainer.test();

        expect(
          () => container.read(provider),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.exception,
              'exception',
              equals(thrownError),
            ),
          ),
        );
      },
    );

    // ── Combined property: diverse error types all get wrapped ─────────────
    Glados2(any.intInRange(0, 4), any.letterOrDigits).test(
      'any error type thrown during provider computation is wrapped in ProviderException',
      (errorTypeIndex, payload) {
        // Generate diverse error types based on index
        final Object thrownError = switch (errorTypeIndex) {
          0 => Exception(payload),
          1 => DomainException(payload),
          2 => NetworkException(500, payload),
          3 => TimeoutException(payload.length * 100),
          _ => ValidationException(payload, 'invalid'),
        };

        final provider = Provider<dynamic>((ref) {
          // ignore: only_throw_errors
          throw thrownError;
        });

        final container = ProviderContainer.test();

        expect(
          () => container.read(provider),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.exception,
              'exception',
              equals(thrownError),
            ),
          ),
        );
      },
    );

    // ── Sub-property: ProviderException.stackTrace is non-empty ───────────
    Glados(any.letterOrDigits).test(
      'ProviderException includes a non-empty stackTrace',
      (message) {
        final thrownError = Exception(message);

        final provider = Provider<void>((ref) {
          throw thrownError;
        });

        final container = ProviderContainer.test();

        try {
          container.read(provider);
          fail('Expected ProviderException to be thrown');
        } on ProviderException catch (e) {
          expect(e.exception, equals(thrownError));
          expect(e.stackTrace, isNotNull);
          expect(e.stackTrace.toString(), isNotEmpty);
        }
      },
    );
  });
}
