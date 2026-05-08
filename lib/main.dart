import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/config/environment.dart';
import 'core/theme/app_theme.dart';
import 'core/time/brazil_time.dart';
import 'features/shared/providers.dart';
import 'features/shared/widgets/error_boundary.dart';
import 'features/admin/presentation/lock_screen.dart';
import 'features/admin/presentation/screens/accept_invite_screen.dart';
import 'features/admin/presentation/screens/driver_justification_page.dart';
import 'features/admin/presentation/screens/review_contract_screen.dart';
import 'core/config/supabase_client.dart';
import 'infrastructure/persistence/persistence_mode.dart';
import 'infrastructure/persistence/persistence_provider.dart';
import 'infrastructure/observability/sentry_observer.dart';
import 'infrastructure/observability/analytics_service.dart';
import 'infrastructure/providers/supabase_provider.dart';
import 'state/providers/sla_providers.dart';
import 'state/providers/auth_providers.dart';
import 'state/retry_policy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

      // Phase 6 — Detect public deep links on Flutter Web startup.
      final uri = Uri.base;
      final queryToken = uri.queryParameters['token'];
      final isInviteRoute =
          uri.path.contains('accept-invite') && queryToken != null;
      final isReviewContractRoute =
          uri.path.contains('review-contract') && queryToken != null;
      final isJustifyRoute = uri.path.contains('justify') && queryToken != null;

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
          ],
          child: VeraProbAdminApp(
            inviteToken: isInviteRoute ? queryToken : null,
            reviewContractToken: isReviewContractRoute ? queryToken : null,
            justifyToken: isJustifyRoute ? queryToken : null,
          ),
        ),
      );
    },
  );
}

class VeraProbAdminApp extends ConsumerStatefulWidget {
  final String? inviteToken;
  final String? reviewContractToken;
  final String? justifyToken;

  const VeraProbAdminApp({
    super.key,
    this.inviteToken,
    this.reviewContractToken,
    this.justifyToken,
  });

  @override
  ConsumerState<VeraProbAdminApp> createState() => _VeraProbAdminAppState();
}

class _VeraProbAdminAppState extends ConsumerState<VeraProbAdminApp> {
  @override
  Widget build(BuildContext context) {
    // FASE 8 — Start the ContractualEvaluationSubscriber reactively.
    // Ensure it only runs when an organizationId is available in the session.
    // This prevents the StateError on startup when use is not logged in.
    ref.listen(currentOrganizationIdProvider, (previous, next) {
      if (next != null) {
        ref.read(contractualEvaluationSubscriberProvider)?.start();
      }
    });

    return MaterialApp(
      title: 'veraprob — Control Center',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      // 8.4 — Sentry route tracking (no-op when Sentry is disabled in dev)
      navigatorObservers: [SentryNavigatorObserver()],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      locale: const Locale('pt', 'BR'),
      home: widget.justifyToken != null
          ? DriverJustificationPage(token: widget.justifyToken!)
          : widget.reviewContractToken != null
          ? ReviewContractScreen(token: widget.reviewContractToken!)
          : widget.inviteToken != null
          ? AcceptInviteScreen(token: widget.inviteToken!)
          : const ErrorBoundary(child: AdminLockScreen()),
    );
  }
}
