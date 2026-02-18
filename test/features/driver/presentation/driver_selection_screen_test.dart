import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/features/driver/presentation/driver_selection_screen.dart';
import 'package:busflow/features/shared/providers.dart';
import 'package:busflow/features/driver/domain/entities/driver.dart';
import 'package:busflow/features/driver/data/repositories/driver_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class FakeDriverRepository implements IDriverRepository {
  @override
  Future<List<Driver>> getDrivers() async {
    return [
      const Driver(id: '1', name: 'João Silva', licenseNumber: '12345678900'),
      const Driver(
        id: '2',
        name: 'Maria Oliveira',
        licenseNumber: '98765432100',
      ),
    ];
  }

  @override
  Future<void> addDriver(Driver driver) async {}

  @override
  Future<void> deleteDriver(String id) async {}

  @override
  Future<void> updateDriver(Driver driver) async {}
}

class ErrorDriverRepository implements IDriverRepository {
  @override
  Future<List<Driver>> getDrivers() async {
    throw Exception('Network error');
  }

  @override
  Future<void> addDriver(Driver driver) async {
    throw Exception('Network error');
  }

  @override
  Future<void> deleteDriver(String id) async {
    throw Exception('Network error');
  }

  @override
  Future<void> updateDriver(Driver driver) async {
    throw Exception('Network error');
  }
}

void main() {
  late MockSharedPreferences mockSharedPreferences;

  setUp(() {
    mockSharedPreferences = MockSharedPreferences();
    when(() => mockSharedPreferences.getStringList(any())).thenReturn([]);
    when(
      () => mockSharedPreferences.setStringList(any(), any()),
    ).thenAnswer((_) async => true);
  });

  Widget buildSelectionScreen({IDriverRepository? repository}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        driverRepositoryProvider.overrideWithValue(
          repository ?? FakeDriverRepository(),
        ),
      ],
      child: const MaterialApp(home: DriverSelectionScreen()),
    );
  }

  group('DriverSelectionScreen - Rendering', () {
    testWidgets('renders AppBar with correct title', (tester) async {
      await tester.pumpWidget(buildSelectionScreen());
      await tester.pump();
      expect(find.text('Identificação do Motorista'), findsOneWidget);
    });

    testWidgets('renders badge icon', (tester) async {
      await tester.pumpWidget(buildSelectionScreen());
      await tester.pump();
      expect(find.byIcon(Icons.badge), findsOneWidget);
    });

    testWidgets('renders "Quem é você?" heading', (tester) async {
      await tester.pumpWidget(buildSelectionScreen());
      await tester.pump();
      expect(find.text('Quem é você?'), findsOneWidget);
    });

    testWidgets('renders CONFIRMAR button', (tester) async {
      await tester.pumpWidget(buildSelectionScreen());
      await tester.pump();
      expect(find.text('CONFIRMAR'), findsOneWidget);
    });
  });

  group('DriverSelectionScreen - Loading State', () {
    testWidgets('shows loading indicator while drivers are loading', (
      tester,
    ) async {
      await tester.pumpWidget(buildSelectionScreen());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows dropdown after drivers are loaded', (tester) async {
      await tester.pumpWidget(buildSelectionScreen());
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<Driver>), findsOneWidget);
    });
  });

  group('DriverSelectionScreen - Button State', () {
    testWidgets('CONFIRMAR button is disabled when no driver is selected', (
      tester,
    ) async {
      await tester.pumpWidget(buildSelectionScreen());
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'CONFIRMAR'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('dropdown shows driver names after loading', (tester) async {
      await tester.pumpWidget(buildSelectionScreen());
      await tester.pumpAndSettle();

      // Open the dropdown to verify its contents
      await tester.tap(find.byType(DropdownButtonFormField<Driver>));
      await tester.pumpAndSettle();

      expect(find.text('João Silva'), findsWidgets);
      expect(find.text('Maria Oliveira'), findsWidgets);
    });
  });

  group('DriverSelectionScreen - Error State', () {
    testWidgets('shows error message when repository fails', (tester) async {
      await tester.pumpWidget(
        buildSelectionScreen(repository: ErrorDriverRepository()),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Erro ao carregar motoristas'),
        findsOneWidget,
      );
    });
  });
}
