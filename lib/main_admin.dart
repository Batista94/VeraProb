import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'presentation/shell/admin_shell.dart';
import 'presentation/screens/command_center/command_center_screen.dart';
import 'presentation/screens/trips/trips_timeline_screen.dart';
import 'presentation/screens/resources/resource_management_screen.dart';
import 'presentation/screens/system/system_health_screen.dart';
import 'features/shared/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
        },
      ),
    );
  }
}
