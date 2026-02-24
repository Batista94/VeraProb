import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/features/admin/presentation/timecard_reports_screen.dart';
import 'package:busflow/features/shared/providers.dart';
import 'package:busflow/features/driver/domain/entities/driver.dart';
import 'package:busflow/features/shared/domain/entities/trip.dart';
import 'package:busflow/features/driver/data/repositories/driver_repository.dart';
import 'package:busflow/features/shared/data/repositories/trip_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockDriverRepository extends Mock implements IDriverRepository {}

class MockTripRepository extends Mock implements ITripRepository {}

void main() {
  late MockSharedPreferences mockSharedPreferences;
  late MockDriverRepository mockDriverRepository;
  late MockTripRepository mockTripRepository;

  setUp(() {
    mockSharedPreferences = MockSharedPreferences();
    mockDriverRepository = MockDriverRepository();
    mockTripRepository = MockTripRepository();

    when(() => mockSharedPreferences.getStringList(any())).thenReturn([]);
  });

  Widget buildReportsScreen() {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(mockSharedPreferences),
        driverRepositoryProvider.overrideWithValue(mockDriverRepository),
        tripRepositoryProvider.overrideWithValue(mockTripRepository),
      ],
      child: const MaterialApp(home: TimecardReportsScreen()),
    );
  }

  group('TimecardReportsScreen', () {
    testWidgets('renders empty table when no data', (tester) async {
      when(() => mockDriverRepository.getDrivers()).thenAnswer((_) async => []);
      when(() => mockTripRepository.getTrips()).thenAnswer((_) async => []);

      await tester.pumpWidget(buildReportsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Relatório de Ponto Eletrônico'), findsOneWidget);
      expect(
        find.text('Histórico de viagens e horas trabalhadas.'),
        findsOneWidget,
      );

      expect(find.text('Nenhuma viagem registrada.'), findsOneWidget);
    });

    testWidgets('renders Rows with Data', (tester) async {
      final driver = const Driver(
        id: '1',
        name: 'João Silva',
        licenseNumber: '111',
      );
      final trip = Trip(
        id: 't1',
        routeId: '809U',
        driverId: '1',
        startTime: DateTime(2023, 10, 27, 8, 0),
        endTime: DateTime(2023, 10, 27, 9, 0),
        status: 'completed',
      );

      when(
        () => mockDriverRepository.getDrivers(),
      ).thenAnswer((_) async => [driver]);
      when(() => mockTripRepository.getTrips()).thenAnswer((_) async => [trip]);

      await tester.pumpWidget(buildReportsScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('Motorista: 1'), findsOneWidget);
      expect(find.text('Linha: 809U'), findsOneWidget);
      // expect(find.text('completed'), findsOneWidget); // Status not text, but Icon color

      // Verify Total Hours Card
      // 1 hour trip
      expect(find.text('1h 0m'), findsOneWidget);
    });
  });
}
