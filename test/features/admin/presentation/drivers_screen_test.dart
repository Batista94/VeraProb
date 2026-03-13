import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pactaflow/features/admin/presentation/drivers_screen.dart';
import 'package:pactaflow/features/shared/providers.dart';
import 'package:pactaflow/features/shared/domain/entities/driver.dart';
import 'package:pactaflow/features/shared/data/repositories/driver_repository.dart';
import 'package:pactaflow/domain/enums/user_role.dart';
import 'package:pactaflow/state/providers/auth_providers.dart';
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
        currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
      ],
      child: const MaterialApp(home: Scaffold(body: DriversScreen())),
    );
  }

  group('DriversScreen', () {
    testWidgets('renders Empty State when no drivers', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      expect(find.text('Motoristas da Frota'), findsOneWidget);
      expect(find.text('Nenhum motorista cadastrado ainda.'), findsOneWidget);
      expect(find.text('Cadastrar motorista'), findsOneWidget);
    });

    testWidgets('renders List of Drivers', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer(
        (_) async => [
          const Driver(id: '1', name: 'João Silva', licenseNumber: '111'),
          const Driver(id: '2', name: 'Maria Oliveira', licenseNumber: '222'),
        ],
      );

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      expect(find.text('João Silva'), findsOneWidget);
      expect(find.text('111'), findsOneWidget);
      expect(find.text('Maria Oliveira'), findsOneWidget);
      expect(find.text('Ativo'), findsNWidgets(2));
    });

    testWidgets('Add Driver flow via drawer', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer((_) async => []);
      when(
        () => mockDriverRepository.addDriver(any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      // Tap "Cadastrar motorista" button
      await tester.tap(find.text('Cadastrar motorista'));
      await tester.pumpAndSettle();

      // Verify drawer opened
      expect(
        find.text('Cadastrar motorista'),
        findsNWidgets(2),
      ); // button + drawer title
      expect(
        find.text(
          'Este cadastro registra o motorista na frota. O acesso ao sistema é configurado separadamente.',
        ),
        findsOneWidget,
      );

      // Enter data
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ex: João Carlos da Silva'),
        'Carlos Teste',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ex: 12345678900'),
        '999888777',
      );

      // Tap Cadastrar button in drawer
      await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));

      // Pump enough for async save + animation, but don't use pumpAndSettle
      // (3s highlight timer prevents settling)
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 500));

      // Verify interaction
      verify(() => mockDriverRepository.addDriver(any())).called(1);

      // Advance past highlight timer to avoid pending timer assertion
      await tester.pump(const Duration(seconds: 4));
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

      // Find delete icon
      final deleteButton = find.byIcon(Icons.delete_outline);
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

    testWidgets('Search filters drivers', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer(
        (_) async => [
          const Driver(id: '1', name: 'João Silva', licenseNumber: '111'),
          const Driver(id: '2', name: 'Maria Oliveira', licenseNumber: '222'),
        ],
      );

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      // Both visible initially
      expect(find.text('João Silva'), findsOneWidget);
      expect(find.text('Maria Oliveira'), findsOneWidget);

      // Type search
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar por nome ou CNH...'),
        'João',
      );
      await tester.pumpAndSettle();

      expect(find.text('João Silva'), findsOneWidget);
      expect(find.text('Maria Oliveira'), findsNothing);
    });

    testWidgets('Form validation prevents empty fields', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildDriversScreen());
      await tester.pumpAndSettle();

      // Open drawer
      await tester.tap(find.text('Cadastrar motorista'));
      await tester.pumpAndSettle();

      // Tap Cadastrar without filling fields
      await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar'));
      await tester.pumpAndSettle();

      // Verify validation messages
      expect(find.text('O nome é obrigatório'), findsOneWidget);
      expect(find.text('O número da CNH é obrigatório'), findsOneWidget);

      // Verify addDriver was NOT called
      verifyNever(() => mockDriverRepository.addDriver(any()));
    });
  });
}

