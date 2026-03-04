import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shell/admin_shell.dart';
import 'features/admin/presentation/command_center/command_center_screen.dart';
import 'features/admin/presentation/trips/trips_timeline_screen.dart';
import 'features/admin/presentation/resources/resource_management_screen.dart';
import 'features/admin/presentation/system/system_health_screen.dart';
import 'features/admin/presentation/command_center/screens/operational_audit_screen.dart';
import 'features/shared/providers.dart';
import 'presentation/shell/settings_screen.dart';
import 'core/config/supabase_client.dart';
import 'infrastructure/persistence/persistence_mode.dart';
import 'infrastructure/persistence/persistence_provider.dart';

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

class BusFlowAdminApp extends StatelessWidget {
  const BusFlowAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BusFlow — Control Center',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const AdminShell(
        screens: {
          AdminDestination.commandCenter: CommandCenterScreen(),
          AdminDestination.trips: TripsTimelineScreen(),
          AdminDestination.resources: ResourceManagementScreen(),
          AdminDestination.system: SystemHealthScreen(),
          AdminDestination.audit: OperationalAuditScreen(),
          AdminDestination.settings: SettingsScreen(),
        },
      ),
    );
  }
}
