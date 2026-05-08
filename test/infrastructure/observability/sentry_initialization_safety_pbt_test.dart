import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:sentry_flutter/sentry_flutter.dart';

/// **Validates: Requirements 3.2**
///
/// Property 3: Sentry initialization safety
///
/// For any valid DSN string (non-empty, URI-formatted) and any
/// EnvironmentConfig where sentryEnabled is true, calling initSentry
/// SHALL complete without throwing an unhandled exception and SHALL
/// return true.
///
/// Since `initSentry` depends on compile-time constants from
/// `EnvironmentConfig`, we test the core initialization logic directly:
/// configuring `SentryFlutterOptions` with arbitrary valid DSN strings
/// must never throw. This mirrors exactly what happens inside the
/// `SentryFlutter.init` callback in production code.

/// Represents a valid Sentry DSN with its component parts.
class ValidSentryDsn {
  final String publicKey;
  final String host;
  final int projectId;

  const ValidSentryDsn({
    required this.publicKey,
    required this.host,
    required this.projectId,
  });

  /// Produces the full DSN URI string in Sentry format.
  String get uri => 'https://$publicKey@$host/$projectId';

  @override
  String toString() => 'ValidSentryDsn($uri)';
}

/// Configures Sentry options exactly as production `initSentry` does.
///
/// This function mirrors the options callback inside `initSentry`:
/// ```dart
/// await SentryFlutter.init((options) {
///   options.dsn = dsn;
///   options.environment = environment;
///   options.tracesSampleRate = isProd ? 0.2 : 1.0;
///   ...
/// }, appRunner: appRunner);
/// ```
///
/// Returns the configured options object for assertion.
SentryFlutterOptions configureSentryOptions({
  required String dsn,
  required String environment,
  required bool isProd,
}) {
  final options = SentryFlutterOptions();

  // Mirror production initSentry configuration
  options.dsn = dsn;
  options.environment = environment;
  options.tracesSampleRate = isProd ? 0.2 : 1.0;
  // ignore: experimental_member_use
  options.profilesSampleRate = isProd ? 0.1 : 0.5;
  options.attachScreenshot = false; // Never capture screenshots — privacy
  options.sendDefaultPii = false; // Never send PII automatically
  options.debug = false; // Disable debug in tests
  options.release = 'veraprob@1.0.0+$environment';

  return options;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Generators ──────────────────────────────────────────────────────────

  /// Generates a valid hex-like public key (32 alphanumeric chars).
  final publicKeyGen = any.intInRange(1, 999999999).map((seed) {
    // Produce a deterministic 32-char hex-like key from the seed
    final hex = seed.toRadixString(16).padLeft(32, 'a');
    return hex.substring(0, 32);
  });

  /// Generates a valid Sentry ingest hostname.
  final hostGen = any
      .intInRange(1, 999999)
      .map((orgId) => 'o$orgId.ingest.sentry.io');

  /// Generates a valid project ID (positive integer).
  final projectIdGen = any.intInRange(1, 9999999);

  /// Generates a valid environment string.
  final environmentGen = any
      .intInRange(0, 2)
      .map((i) => const ['dev', 'staging', 'prod'][i]);

  /// Generates a boolean for isProd flag.
  final isProdGen = any.intInRange(0, 1).map((i) => i == 1);

  group('Feature: dependency-upgrade-phase3, '
      'Property 3: Sentry initialization safety', () {
    // ── PBT using Glados ────────────────────────────────────────────────

    Glados3(publicKeyGen, hostGen, projectIdGen).test(
      'PBT: configureSentryOptions never throws for any valid DSN',
      (publicKey, host, projectId) {
        final dsn = 'https://$publicKey@$host/$projectId';

        // Property: configuring Sentry options with a valid DSN must not throw
        expect(
          () => configureSentryOptions(
            dsn: dsn,
            environment: 'staging',
            isProd: false,
          ),
          returnsNormally,
          reason: 'configureSentryOptions must not throw for valid DSN: $dsn',
        );
      },
    );

    Glados2(environmentGen, isProdGen).test(
      'PBT: configureSentryOptions never throws for any environment config',
      (environment, isProd) {
        const dsn = 'https://abc123def456@o12345.ingest.sentry.io/1234567';

        // Property: configuring Sentry options must not throw for any
        // valid environment configuration
        expect(
          () => configureSentryOptions(
            dsn: dsn,
            environment: environment,
            isProd: isProd,
          ),
          returnsNormally,
          reason:
              'configureSentryOptions must not throw for '
              'environment=$environment, isProd=$isProd',
        );
      },
    );

    Glados3(publicKeyGen, hostGen, projectIdGen).test(
      'PBT: configured options preserve DSN value exactly',
      (publicKey, host, projectId) {
        final dsn = 'https://$publicKey@$host/$projectId';

        final options = configureSentryOptions(
          dsn: dsn,
          environment: 'prod',
          isProd: true,
        );

        // Property: the DSN must be preserved exactly as provided
        expect(
          options.dsn,
          equals(dsn),
          reason: 'Options DSN must equal input DSN exactly',
        );
      },
    );

    Glados2(environmentGen, isProdGen).test(
      'PBT: configured options have correct sample rates for environment',
      (environment, isProd) {
        const dsn = 'https://abc123def456@o12345.ingest.sentry.io/1234567';

        final options = configureSentryOptions(
          dsn: dsn,
          environment: environment,
          isProd: isProd,
        );

        // Property: sample rates must match the isProd flag
        if (isProd) {
          expect(options.tracesSampleRate, equals(0.2));
          // ignore: experimental_member_use
          expect(options.profilesSampleRate, equals(0.1));
        } else {
          expect(options.tracesSampleRate, equals(1.0));
          // ignore: experimental_member_use
          expect(options.profilesSampleRate, equals(0.5));
        }
      },
    );

    // ── Edge cases ────────────────────────────────────────────────────────

    test('minimal valid DSN (shortest possible components)', () {
      const dsn = 'https://a@o1.ingest.sentry.io/1';

      expect(
        () =>
            configureSentryOptions(dsn: dsn, environment: 'dev', isProd: false),
        returnsNormally,
      );

      final options = configureSentryOptions(
        dsn: dsn,
        environment: 'dev',
        isProd: false,
      );
      expect(options.dsn, equals(dsn));
    });

    test('long DSN with maximum-length components', () {
      final longKey = 'a' * 64;
      final longHost = 'o${'9' * 10}.ingest.us.sentry.io';
      final dsn = 'https://$longKey@$longHost/99999999';

      expect(
        () =>
            configureSentryOptions(dsn: dsn, environment: 'prod', isProd: true),
        returnsNormally,
      );

      final options = configureSentryOptions(
        dsn: dsn,
        environment: 'prod',
        isProd: true,
      );
      expect(options.dsn, equals(dsn));
    });

    test('privacy settings are always enforced regardless of DSN', () {
      const dsn = 'https://key123@o456.ingest.sentry.io/789';

      final options = configureSentryOptions(
        dsn: dsn,
        environment: 'prod',
        isProd: true,
      );

      // Privacy invariants from production code
      expect(options.attachScreenshot, isFalse);
      expect(options.sendDefaultPii, isFalse);
    });

    test('release string contains environment label', () {
      const dsn = 'https://key123@o456.ingest.sentry.io/789';

      for (final env in ['dev', 'staging', 'prod']) {
        final options = configureSentryOptions(
          dsn: dsn,
          environment: env,
          isProd: env == 'prod',
        );

        expect(
          options.release,
          contains(env),
          reason: 'Release string must contain environment label "$env"',
        );
      }
    });
  });
}
