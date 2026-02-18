import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'features/passenger/presentation/map_screen.dart';
import 'features/shared/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BusFlowPassengerApp(),
    ),
  );
}

class BusFlowPassengerApp extends StatelessWidget {
  const BusFlowPassengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BusFlow - Passageiro',
      theme: AppTheme.lightTheme,
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
