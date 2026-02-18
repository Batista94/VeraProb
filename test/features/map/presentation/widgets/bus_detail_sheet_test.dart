import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busflow/features/passenger/presentation/widgets/bus_detail_sheet.dart';
import 'package:busflow/features/shared/domain/entities/vehicle_position.dart';
import 'package:busflow/features/shared/providers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late MockSharedPreferences mockPrefs;

  setUp(() {
    mockPrefs = MockSharedPreferences();
    when(() => mockPrefs.getStringList(any())).thenReturn([]);
    when(
      () => mockPrefs.setStringList(any(), any()),
    ).thenAnswer((_) async => true);
  });

  final dummyVehicle = VehiclePosition(
    tripId: 'Trip123',
    latitude: -23.55,
    longitude: -46.63,
    timestamp: DateTime.now(),
    source: 'api_public',
    routeName: '809U Term. Lapa',
    speed: 10.0,
  );

  testWidgets('BusDetailSheet displays vehicle info', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          userLocationStreamProvider.overrideWith(
            (ref) => Stream.value(
              Position(
                longitude: -46.635,
                latitude: -23.555,
                timestamp: DateTime.now(),
                accuracy: 10,
                altitude: 0,
                heading: 0,
                speed: 0,
                speedAccuracy: 0,
                altitudeAccuracy: 0,
                headingAccuracy: 0,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusDetailSheet(vehicle: dummyVehicle, onReport: (val) {}),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Trip123'), findsOneWidget);
    // Check speed conversion (10 m/s * 3.6 = 36 km/h)
    expect(find.text('36 km/h'), findsOneWidget);
  });

  testWidgets('BusDetailSheet toggles favorite on tap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          userLocationStreamProvider.overrideWith((ref) => Stream.empty()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusDetailSheet(vehicle: dummyVehicle, onReport: (val) {}),
          ),
        ),
      ),
    );

    // Initial state: not favorite (border star)
    expect(find.byIcon(Icons.star_border), findsOneWidget);

    // Tap favorite
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pumpAndSettle(); // Settle animations

    // Checked state: favorite (filled star)
    expect(find.byIcon(Icons.star), findsOneWidget);

    // Verify persistence called
    verify(
      () => mockPrefs.setStringList('favorite_routes', ['Trip123']),
    ).called(1);
  });

  testWidgets('BusDetailSheet displays Colaborativo badge for driver source', (
    WidgetTester tester,
  ) async {
    final driverVehicle = VehiclePosition(
      tripId: 'DriverTrip',
      latitude: -23.55,
      longitude: -46.63,
      timestamp: DateTime.now(),
      source: 'driver_app_gps',
      routeName: '809U Term. Lapa',
      speed: 5.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          userLocationStreamProvider.overrideWith((ref) => Stream.empty()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusDetailSheet(vehicle: driverVehicle, onReport: (val) {}),
          ),
        ),
      ),
    );

    await tester.pump();

    // Should show Colaborativo badge instead of Oficial
    expect(find.text('Colaborativo'), findsOneWidget);
  });

  testWidgets('BusDetailSheet report button triggers onReport callback', (
    WidgetTester tester,
  ) async {
    String? reportedLabel;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          userLocationStreamProvider.overrideWith((ref) => Stream.empty()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BusDetailSheet(
              vehicle: dummyVehicle,
              onReport: (val) => reportedLabel = val,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    // Tap the Lotação report button
    await tester.tap(find.text('Lotação'));
    await tester.pump();

    expect(reportedLabel, 'Lotação');
  });
}
