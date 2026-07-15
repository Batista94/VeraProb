import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/domain/admin/data_seeding_repository.dart';
import 'package:veraprob/features/admin/presentation/dashboard_screen.dart';
// import 'package:veraprob/features/admin/presentation/widgets/charts_section.dart';
// import 'package:veraprob/features/admin/presentation/widgets/heatmap_section.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockDataSeedingRepository extends Mock implements DataSeedingRepository {}

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
        currentUserRoleProvider.overrideWithValue(UserRole.admin),
        currentOrganizationIdProvider.overrideWithValue('org-test-001'),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
    );
  }

  group('DashboardScreen seed error (UX-RAW-EXCEPTION guard)', () {
    testWidgets('seed failure shows sanitised domain message', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;

      final mockRepo = MockDataSeedingRepository();
      when(() => mockRepo.seedCsvData(any())).thenThrow(Exception('network'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
            dataSeedingRepositoryProvider.overrideWithValue(mockRepo),
            currentOrganizationIdProvider.overrideWithValue('org-1'),
            currentUserRoleProvider.overrideWithValue(UserRole.admin),
          ],
          child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SIMULAR OPERAÇÃO'));
      await tester.pumpAndSettle();

      expect(
        find.text('Erro ao inserir dados de simulação. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('network'), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });

  group('DashboardScreen', () {
    testWidgets('renders all sections', (tester) async {
      // Set surface size large enough for dashboard items
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(find.text('Painel de Controle'), findsOneWidget);
      expect(
        find.text('Operação em Tempo Real • Receita Protegida'),
        findsOneWidget,
      );

      // Telemetry confidence Bento cell (promoted from app-bar badge)
      expect(find.text('SAÚDE DA INGESTÃO DE TELEMETRIA'), findsOneWidget);

      // Command feed panel
      expect(find.text('Viagens Programadas (Turnos)'), findsOneWidget);

      // Seed Button (debug only)
      expect(find.text('SIMULAR OPERAÇÃO'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('Seed Data button is clickable', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      final button = find.text('SIMULAR OPERAÇÃO');
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
