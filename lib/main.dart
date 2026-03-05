import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'features/shared/providers.dart';
import 'features/shared/widgets/error_boundary.dart';
import 'features/admin/presentation/lock_screen.dart';
import 'core/config/supabase_client.dart';
import 'infrastructure/persistence/persistence_mode.dart';
import 'infrastructure/persistence/persistence_provider.dart';
import 'state/providers/sla_providers.dart';

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
      child: const BusFlowAdminApp(),
    ),
  );
}

class BusFlowAdminApp extends ConsumerStatefulWidget {
  const BusFlowAdminApp({super.key});

  @override
  ConsumerState<BusFlowAdminApp> createState() => _BusFlowAdminAppState();
}

class _BusFlowAdminAppState extends ConsumerState<BusFlowAdminApp> {
  @override
  void initState() {
    super.initState();
    // FASE 8 — Start the ContractualEvaluationSubscriber.
    // Eagerly initializes stream listening and sweep timer.
    Future.microtask(() {
      ref.read(contractualEvaluationSubscriberProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BusFlow — Control Center',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const ErrorBoundary(child: AdminLockScreen()),
    );
  }
}
