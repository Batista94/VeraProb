import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'features/shared/providers.dart';
import 'features/shared/widgets/error_boundary.dart';
import 'features/admin/presentation/lock_screen.dart';
import 'core/config/supabase_client.dart';
import 'infrastructure/persistence/persistence_mode.dart';
import 'infrastructure/persistence/persistence_provider.dart';
import 'state/providers/sla_providers.dart';
import 'state/providers/auth_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FASE 0 - Passively initialize Supabase. No overrides or dependencies created.
  await SupabaseConfig.initialize();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // FASE 6 — Atomic Switch: runtime now operates on Postgres.
        persistenceModeProvider.overrideWithValue(PersistenceMode.postgres),
      ],
      child: const PactaFlowAdminApp(),
    ),
  );
}

class PactaFlowAdminApp extends ConsumerStatefulWidget {
  const PactaFlowAdminApp({super.key});

  @override
  ConsumerState<PactaFlowAdminApp> createState() => _PactaFlowAdminAppState();
}

class _PactaFlowAdminAppState extends ConsumerState<PactaFlowAdminApp> {
  @override
  Widget build(BuildContext context) {
    // FASE 8 — Start the ContractualEvaluationSubscriber reactively.
    // Ensure it only runs when an organizationId is available in the session.
    // This prevents the StateError on startup when use is not logged in.
    ref.listen(currentOrganizationIdProvider, (previous, next) {
      if (next != null) {
        ref.read(contractualEvaluationSubscriberProvider).start();
      } else {
        // If logged out, we should stop the subscriber to clear resources
        ref.read(contractualEvaluationSubscriberProvider).stop();
      }
    });

    return MaterialApp(
      title: 'PactaFlow — Control Center',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      locale: const Locale('pt', 'BR'),
      home: const ErrorBoundary(child: AdminLockScreen()),
    );
  }
}
