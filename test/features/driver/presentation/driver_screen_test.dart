import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:busflow/features/driver/presentation/driver_screen.dart';
import 'package:busflow/features/shared/providers.dart';
import 'package:busflow/features/driver/presentation/tracking_service.dart';
import 'package:busflow/features/driver/domain/entities/driver.dart';

class MockTrackingService extends Mock implements TrackingService {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late MockTrackingService mockTrackingService;
  late MockSharedPreferences mockSharedPreferences;

  setUp(() {
    mockTrackingService = MockTrackingService();
    mockSharedPreferences = MockSharedPreferences();

    when(() => mockSharedPreferences.getStringList(any())).thenReturn([]);
    when(
      () => mockSharedPreferences.setStringList(any(), any()),
    ).thenAnswer((_) async => true);
    when(
      () => mockTrackingService.startTracking(any(), any()),
    ).thenAnswer((_) async {});

    when(() => mockTrackingService.stopTracking()).thenAnswer((_) async {});
  });

  void setViewport(WidgetTester tester) {
    // Use a very wide viewport to prevent horizontal overflow from long text
    tester.view.physicalSize = const Size(1440, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildDriverScreen({Driver? driver}) {
    return ProviderScope(
      overrides: [
        trackingServiceProvider.overrideWithValue(mockTrackingService),
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        if (driver != null) currentDriverProvider.overrideWith((ref) => driver),
      ],
      child: const MaterialApp(home: DriverScreen()),
    );
  }

  group('DriverScreen - Rendering', () {
    testWidgets('renders AppBar with correct title', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.text('Motorista - BusFlow'), findsOneWidget);
    });

    testWidgets('renders logout icon', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('renders INICIAR VIAGEM button', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.text('INICIAR VIAGEM'), findsOneWidget);
    });

    testWidgets('renders bus icon', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.byIcon(Icons.directions_bus), findsOneWidget);
    });

    testWidgets('renders line dropdown', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Selecione a Linha'), findsOneWidget);
    });

    testWidgets('renders route icon', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.byIcon(Icons.directions_bus), findsWidgets);
    });

    testWidgets('renders location off icon initially', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.byIcon(Icons.location_off), findsOneWidget);
    });
  });

  group('DriverScreen - Driver Info', () {
    testWidgets('shows driver name and CNH when set', (tester) async {
      setViewport(tester);
      const driver = Driver(
        id: '1',
        name: 'João Silva',
        licenseNumber: '12345678900',
      );
      await tester.pumpWidget(buildDriverScreen(driver: driver));
      await tester.pump();
      expect(find.text('João Silva'), findsOneWidget);
      expect(find.text('CNH: 12345678900'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('hides driver info when no driver set', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('shows CircleAvatar for driver', (tester) async {
      setViewport(tester);
      const driver = Driver(id: '2', name: 'Maria', licenseNumber: '999');
      await tester.pumpWidget(buildDriverScreen(driver: driver));
      await tester.pump();
      expect(find.byType(CircleAvatar), findsOneWidget);
    });
  });

  group('DriverScreen - Tracking', () {
    testWidgets('shows warning snackbar without selecting a line', (
      tester,
    ) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      await tester.tap(find.text('INICIAR VIAGEM'));
      await tester.pump();
      expect(
        find.text('⚠️ Por favor, selecione uma linha antes de iniciar.'),
        findsOneWidget,
      );
    });

    testWidgets('dropdown opens and shows line items', (tester) async {
      setViewport(tester);
      await tester.pumpWidget(buildDriverScreen());
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.textContaining('809U-10'), findsWidgets);
    });

    testWidgets('selecting a line updates dropdown and enables tracking', (
      tester,
    ) async {
      setViewport(tester);
      const driver = Driver(id: '1', name: 'João', licenseNumber: '123');
      await tester.pumpWidget(buildDriverScreen(driver: driver));
      await tester.pump();

      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Select the first line
      final items = find.textContaining('809U-10');
      await tester.tap(items.last);
      await tester.pumpAndSettle();

      // Start tracking - use pump() not pumpAndSettle() because
      // LinearProgressIndicator runs an infinite animation
      await tester.tap(find.text('INICIAR VIAGEM'));
      await tester.pump();

      // Button should change to ENCERRAR VIAGEM
      expect(find.text('ENCERRAR VIAGEM'), findsOneWidget);

      // Tracking status card should appear
      expect(find.textContaining('EM VIAGEM'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Verify startTracking was called
      verify(() => mockTrackingService.startTracking(any(), any())).called(1);
    });

    testWidgets('starting tracking shows viagem iniciada snackbar', (
      tester,
    ) async {
      setViewport(tester);
      const driver = Driver(id: '1', name: 'João', licenseNumber: '123');
      await tester.pumpWidget(buildDriverScreen(driver: driver));
      await tester.pump();

      // Select a line
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      final items = find.textContaining('809U-10');
      await tester.tap(items.last);
      await tester.pumpAndSettle();

      // Start tracking
      await tester.tap(find.text('INICIAR VIAGEM'));
      await tester.pump();

      expect(find.textContaining('Viagem iniciada'), findsOneWidget);
    });
  });
}
