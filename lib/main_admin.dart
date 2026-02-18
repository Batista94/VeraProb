import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'features/shared/providers.dart';
import 'features/admin/presentation/lock_screen.dart';

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
      title: 'BusFlow - Admin',
      theme: AppTheme.lightTheme,
      home: const AdminLockScreen(), // Start with Lock Screen
      debugShowCheckedModeBanner: false,
    );
  }
}
