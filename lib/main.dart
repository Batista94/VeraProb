import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app/routing/app_router.dart';
import 'infrastructure/config/environment.dart';
import 'core/theme/app_theme.dart';
import 'domain/shared/brazil_time.dart';
import 'features/shared/providers.dart';
import 'infrastructure/config/supabase_client.dart';
import 'infrastructure/persistence/persistence_mode.dart';
import 'infrastructure/persistence/persistence_provider.dart';
import 'infrastructure/observability/sentry_observer.dart';
import 'infrastructure/observability/analytics_service.dart';
import 'infrastructure/providers/supabase_provider.dart';
import 'state/providers/sla_providers.dart';
import 'state/providers/auth_providers.dart';
import 'state/retry_policy.dart';

/// Test-only overrides to inject mocks during E2E testing.
@visibleForTesting
List<Override> testProviderOverrides = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // INV-17: path-based URLs (real paths, not hash) so every screen is
  // deep-linkable and F5 restores it. Uses dart:js_interop internally — no
  // dart:html / legacy js.
  usePathUrlStrategy();
  BrazilTime.ensureInitialized(); // timezone DB must be ready before ShiftPattern.create()

  // Bootstrap environment
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Expected in CI/CD where --dart-define is used
  }

  // Security Log (Debug only)
  if (kDebugMode) {
    print(
      '[veraprob] Mode: ${EnvironmentConfig.label} | Endpoint: ${EnvironmentConfig.supabaseUrl}',
    );
  }

  // FASE 0 - Passively initialize Supabase. No overrides or dependencies created.
  await SupabaseConfig.initialize();

  // 8.4 — Sentry wraps the entire app startup.
  // initSentry is a no-op in dev or when SENTRY_DSN is not set.
  await initSentry(
    appRunner: () async {
      // 8.4 — Initialize PostHog analytics (no-op in dev).
      // Initialized AFTER Sentry as requested.
      await AnalyticsService.initialize();

      final prefs = await SharedPreferences.getInstance();

      runApp(
        ProviderScope(
          observers: const [SentryRiverpodObserver()],
          retry: classifyForRetry,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            // INV-30: Single bridge — Supabase client injected via Riverpod.
            // All repositories must read from supabaseClientProvider, never
            // access Supabase.instance.client directly.
            supabaseClientProvider.overrideWithValue(supabase),
            // FASE 6 — Atomic Switch: runtime now operates on Postgres.
            persistenceModeProvider.overrideWithValue(PersistenceMode.postgres),
            ...testProviderOverrides,
          ],
          child: const VeraProbAdminApp(),
        ),
      );
    },
  );
}

class VeraProbAdminApp extends ConsumerWidget {
  const VeraProbAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FASE 8 — Start the ContractualEvaluationSubscriber reactively.
    // Ensure it only runs when an organizationId is available in the session.
    // This prevents the StateError on startup when use is not logged in.
    ref.listen(currentOrganizationIdProvider, (previous, next) {
      if (next != null) {
        ref.read(contractualEvaluationSubscriberProvider)?.start();
      }
    });

    // INV-8.5 / AUTH-TRAP: signedOut bounce is handled by the router's
    // `refreshListenable` (AuthRefreshNotifier) — the redirect guard re-runs on
    // every auth event and sends a session-less user back to /login from any
    // screen. Sentry route tracking lives on the GoRouter `observers`.
    return MaterialApp.router(
      title: 'veraprob — Control Center',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(appRouterProvider),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      locale: const Locale('pt', 'BR'),
    );
  }
}
