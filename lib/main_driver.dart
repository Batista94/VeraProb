import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'features/driver/presentation/driver_screen.dart';
import 'features/shared/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BusFlowDriverApp(),
    ),
  );
}

class BusFlowDriverApp extends StatelessWidget {
  const BusFlowDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BusFlow - Motorista',
      theme: AppTheme.lightTheme,
      home: const DriverScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
