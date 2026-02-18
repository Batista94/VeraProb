import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/features/admin/presentation/drivers_screen.dart';
import 'package:busflow/features/shared/providers.dart';
import 'package:busflow/features/driver/domain/entities/driver.dart';
import 'package:busflow/features/driver/data/repositories/driver_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockDriverRepository extends Mock implements IDriverRepository {}

void main() {
  late MockSharedPreferences mockSharedPreferences;
  late MockDriverRepository mockDriverRepository;

  setUp(() {
    mockSharedPreferences = MockSharedPreferences();
    mockDriverRepository = MockDriverRepository();

    when(() => mockSharedPreferences.getStringList(any())).thenReturn([]);

    // Register Fallback Value for Driver
    registerFallbackValue(
      const Driver(id: '0', name: 'Fallback', licenseNumber: '0'),
    );
  });

  Widget buildDriversScreen() {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        driverRepositoryProvider.overrideWithValue(mockDriverRepository),
      ],
      child: const MaterialApp(home: DriversScreen()),
    );
  }

  group('DriversScreen', () {
    testWidgets('renders Empty State when no drivers', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      expect(find.text('Gerenciamento de Motoristas'), findsOneWidget);
      expect(find.text('Nenhum motorista cadastrado.'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('renders List of Drivers', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer(
        (_) async => [
          const Driver(id: '1', name: 'João Silva', licenseNumber: '111'),
          const Driver(id: '2', name: 'Maria Oliveira', licenseNumber: '222'),
        ],
      );

      await tester.pumpWidget(buildDriversScreen());
      // Wait for FutureBuilder/Riverpod
      await tester.pumpAndSettle();

      expect(find.text('João Silva'), findsOneWidget);
      expect(find.text('CNH: 111'), findsOneWidget);
      expect(find.text('Maria Oliveira'), findsOneWidget);
    });

    testWidgets('Add Driver flow', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer((_) async => []);
      when(
        () => mockDriverRepository.addDriver(any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      // Tap Add
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Verify Dialog
      expect(find.text('Novo Motorista'), findsOneWidget);

      // Enter data
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome Completo'),
        'Carlos',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número da CNH'),
        '333',
      );

      // Tap Save
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      // Verify interaction
      verify(() => mockDriverRepository.addDriver(any())).called(1);
    });

    testWidgets('Delete Driver flow', (tester) async {
      final driver = const Driver(
        id: '1',
        name: 'João Silva',
        licenseNumber: '111',
      );
      when(
        () => mockDriverRepository.getDrivers(),
      ).thenAnswer((_) async => [driver]);
      when(
        () => mockDriverRepository.deleteDriver('1'),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      // Find delete icon (IconButton with delete icon)
      final deleteButton = find.byIcon(Icons.delete);
      expect(deleteButton, findsOneWidget);

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      // Verify Confirmation Dialog
      expect(find.text('Confirmar exclusão'), findsOneWidget);

      // Tap Confirm
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      // Verify interaction
      verify(() => mockDriverRepository.deleteDriver('1')).called(1);
    });
  });
}
