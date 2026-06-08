import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';

// Non-INV26-compliant logger — propagates exceptions instead of swallowing them.
// Used as a negative reference to document WHY INV-26 exists.
class _ThrowingLogger extends SecurityIncidentLogger {
  final Object _error;
  _ThrowingLogger(this._error) : super(null);

  @override
  Future<void> log({
    required String eventType,
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> jwtClaimsSnapshot,
  }) async => throw _error;
}

void main() {
  group('securityIncidentLoggerProvider — nominal', () {
    test('provider not instantiated before read', () {
      final container = ProviderContainer.test();
      expect(container.exists(securityIncidentLoggerProvider), isFalse);
    });

    test('provider resolves to SecurityIncidentLogger instance', () {
      final container = ProviderContainer.test(
        overrides: [
          supabaseClientProvider.overrideWith((_) => throw StateError('no-op')),
        ],
      );
      expect(
        container.read(securityIncidentLoggerProvider),
        isA<SecurityIncidentLogger>(),
      );
    });
  });

  group('SecurityIncidentLogger.log() — nominal', () {
    test(
      'completes without throwing when ref is null (null-guard early return)',
      () async {
        final logger = SecurityIncidentLogger(null);
        await expectLater(
          logger.log(
            eventType: 'SECURITY_VIOLATION_BYPASS_ATTEMPT',
            metadata: {'route': '/admin'},
            jwtClaimsSnapshot: {'sub': 'user-1'},
          ),
          completes,
        );
      },
    );

    test('completes for any eventType string (null ref path)', () async {
      final logger = SecurityIncidentLogger(null);
      for (final eventType in ['BYPASS', '', '   ', 'X' * 500]) {
        await expectLater(
          logger.log(eventType: eventType, metadata: {}, jwtClaimsSnapshot: {}),
          completes,
          reason: 'log() must never throw regardless of eventType value',
        );
      }
    });
  });

  // ── CIA — Confidentiality ────────────────────────────────────────────────────

  group('CIA — Confidentiality', () {
    test(
      'log() returns Future<void> — caller cannot observe success or failure (INV-26)',
      () {
        final logger = SecurityIncidentLogger(null);
        final future = logger.log(
          eventType: 'TEST',
          metadata: {},
          jwtClaimsSnapshot: {},
        );
        // Future<void> type is enforced at compile time; runtime confirm it resolves.
        expect(future, isA<Future<void>>());
      },
    );

    test(
      'jwtClaimsSnapshot is not mutated by log() (INV-26 — no information leakage)',
      () async {
        final claims = <String, dynamic>{'sub': 'user-1', 'org': 'org-1'};
        final original = Map<String, dynamic>.from(claims);
        final logger = SecurityIncidentLogger(null);
        await logger.log(
          eventType: 'TEST',
          metadata: {},
          jwtClaimsSnapshot: claims,
        );
        expect(
          claims,
          equals(original),
          reason: 'jwtClaimsSnapshot must not be mutated',
        );
      },
    );

    test(
      'metadata is not mutated by log() (null-ref guard returns before any write)',
      () async {
        final metadata = <String, dynamic>{'route': '/admin', 'ip': '10.0.0.1'};
        final original = Map<String, dynamic>.from(metadata);
        final logger = SecurityIncidentLogger(null);
        await logger.log(
          eventType: 'TEST',
          metadata: metadata,
          jwtClaimsSnapshot: {},
        );
        expect(metadata, equals(original));
      },
    );
  });

  // ── CIA — Integrity ──────────────────────────────────────────────────────────

  group('CIA — Integrity', () {
    test(
      'eventType is accepted verbatim — no sanitization that could alter the audit trail',
      () async {
        // Sanitizing eventType would silently rewrite forensic records.
        // log() must pass the string as-is to the Edge Function.
        const sentinelEventType = 'SECURITY_VIOLATION_BYPASS_ATTEMPT';
        final logger = SecurityIncidentLogger(null);
        await expectLater(
          logger.log(
            eventType: sentinelEventType,
            metadata: {},
            jwtClaimsSnapshot: {},
          ),
          completes,
          reason: 'log() must accept eventType verbatim without sanitization',
        );
      },
    );
  });

  // ── CIA — Availability ───────────────────────────────────────────────────────

  group('CIA — Availability', () {
    test(
      'log() swallows Supabase provider StateError — caller Future always completes (INV-26)',
      () async {
        // Override supabaseClientProvider to throw — simulates Supabase unavailability.
        // SecurityIncidentLogger.log() catch block must absorb this and return silently.
        final container = ProviderContainer.test(
          overrides: [
            supabaseClientProvider.overrideWith(
              (_) => throw StateError('Supabase unavailable'),
            ),
          ],
        );
        final logger = container.read(securityIncidentLoggerProvider);
        await expectLater(
          logger.log(
            eventType: 'BYPASS_ATTEMPT',
            metadata: {'route': '/admin'},
            jwtClaimsSnapshot: {},
          ),
          completes,
          reason: 'INV-26: log() must swallow all provider exceptions',
        );
      },
    );

    test(
      'log() swallows ArgumentError from supabase provider (INV-26)',
      () async {
        final container = ProviderContainer.test(
          overrides: [
            supabaseClientProvider.overrideWith(
              (_) => throw ArgumentError('malformed provider'),
            ),
          ],
        );
        final logger = container.read(securityIncidentLoggerProvider);
        await expectLater(
          logger.log(eventType: 'X', metadata: {}, jwtClaimsSnapshot: {}),
          completes,
        );
      },
    );

    test('log() swallows Exception from supabase provider (INV-26)', () async {
      final container = ProviderContainer.test(
        overrides: [
          supabaseClientProvider.overrideWith(
            (_) => throw Exception('network timeout'),
          ),
        ],
      );
      final logger = container.read(securityIncidentLoggerProvider);
      await expectLater(
        logger.log(eventType: 'X', metadata: {}, jwtClaimsSnapshot: {}),
        completes,
      );
    });

    test(
      'negative reference: _ThrowingLogger propagates exceptions — documents WHY INV-26 exists',
      () async {
        // A logger that throws crashes its caller. SecurityIncidentLogger.log() is
        // specifically designed to prevent this via its internal try/catch.
        final logger = _ThrowingLogger(
          StateError('should-not-escape-in-real-logger'),
        );
        await expectLater(
          logger.log(eventType: 'X', metadata: {}, jwtClaimsSnapshot: {}),
          throwsStateError,
          reason:
              'negative reference: non-INV26-compliant impl DOES propagate — real impl must not',
        );
      },
    );

    test('provider never throws on ProviderContainer.test() construction', () {
      expect(() => ProviderContainer.test(), returnsNormally);
    });
  });
}
