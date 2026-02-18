import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/features/admin/presentation/dashboard_screen.dart';
// import 'package:busflow/features/admin/presentation/widgets/charts_section.dart';
// import 'package:busflow/features/admin/presentation/widgets/heatmap_section.dart';
import 'package:busflow/features/shared/providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  late MockSharedPreferences mockSharedPreferences;

  setUp(() {
    mockSharedPreferences = MockSharedPreferences();
    when(() => mockSharedPreferences.getStringList(any())).thenReturn([]);
    HttpOverrides.global = MockHttpOverrides(); // Mock network
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  Widget buildDashboard() {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    );
  }

  group('DashboardScreen', () {
    testWidgets('renders all sections', (tester) async {
      // Set surface size large enough for dashboard items
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(find.text('Visão Geral'), findsOneWidget);
      expect(find.text('Monitoramento de frota e métricas'), findsOneWidget);

      // Charts Section
      expect(find.text('Viagens por Hora (Últimas 24h)'), findsOneWidget);

      // Heatmap Section
      expect(find.text('Mapa de Calor (Lotação)'), findsOneWidget);

      // Seed Button
      expect(find.text('Carregar Dados Teste'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('Seed Data button is clickable', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      final button = find.text('Carregar Dados Teste');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      // Can't verify SnackBar easily if it relies on async DataSeeder,
      // unless we mock supabase/dataseeder.
      // But verifying it's tappable is a good start.

      addTearDown(tester.view.resetPhysicalSize);
    });
  });
}
