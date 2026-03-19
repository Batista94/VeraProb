/// Sentry integration for PactaFlow — 8.4 Observabilidade
///
/// Provides:
/// - [SentryRiverpodObserver]: catches AsyncError from Riverpod providers
/// - Helpers to initialize Sentry via [SentryFlutter]
///
/// Lives in Infrastructure — never import from Domain (INV-4).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/config/environment.dart';

/// Riverpod ProviderObserver that forwards AsyncError states to Sentry.
///
/// Attach to [ProviderScope] in main.dart.
/// Only reports errors in staging/prod; in dev it prints to console.
class SentryRiverpodObserver extends ProviderObserver {
  const SentryRiverpodObserver();

  @override
  void didUpdateProvider(
    ProviderBase<dynamic> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (newValue is AsyncError) {
      final error = newValue.error;
      final stack = newValue.stackTrace;

      if (kDebugMode) {
        debugPrint('[Sentry] Provider error in ${provider.name ?? provider.runtimeType}: $error');
      }

      if (EnvironmentConfig.sentryEnabled) {
        Sentry.captureException(
          error,
          stackTrace: stack,
          hint: Hint.withMap({
            'provider': provider.name ?? provider.runtimeType.toString(),
          }),
        );
      }
    }
  }
}

/// Builds the Sentry DSN and validates it prior to initialization.
///
/// Returns `true` if Sentry was successfully configured.
/// Returns `false` (and logs warning) if DSN is missing.
Future<bool> initSentry({
  required AppRunner appRunner,
}) async {
  if (!EnvironmentConfig.sentryEnabled) {
    if (kDebugMode) {
      debugPrint('[Sentry] Disabled in ${EnvironmentConfig.label} — skipping init.');
    }
    await appRunner();
    return false;
  }

  if (EnvironmentConfig.sentryDsn.isEmpty) {
    debugPrint(
      '[Sentry] ⚠️ SENTRY_DSN not set for ${EnvironmentConfig.label} — error reporting disabled.',
    );
    await appRunner();
    return false;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = EnvironmentConfig.sentryDsn;
      options.environment = EnvironmentConfig.sentryEnvironment;
      options.tracesSampleRate = EnvironmentConfig.isProd ? 0.2 : 1.0;
      options.profilesSampleRate = EnvironmentConfig.isProd ? 0.1 : 0.5; // ignore: experimental_member_use
      options.attachScreenshot = false; // Never capture screenshots — privacy
      options.sendDefaultPii = false;   // Never send PII automatically
      options.debug = kDebugMode;
      options.release = 'pactaflow@${const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0')}+${EnvironmentConfig.sentryEnvironment}';
    },
    appRunner: appRunner,
  );

  if (kDebugMode) {
    debugPrint('[Sentry] Initialized — DSN configured for ${EnvironmentConfig.label}');
  }

  return true;
}
