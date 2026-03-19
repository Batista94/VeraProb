import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/stops/data/repositories/bus_stop_repository.dart';
import 'package:veraprob/features/stops/domain/entities/bus_stop.dart';

void main() {
  group('BusStopRepository', () {
    late BusStopRepository repository;

    setUp(() {
      repository = BusStopRepository();
    });

    test('getNearbyStops should return a non-empty list', () async {
      final stops = await repository.getNearbyStops(-23.5505, -46.6333);
      expect(stops, isNotEmpty);
    });

    test('getNearbyStops should return BusStop instances', () async {
      final stops = await repository.getNearbyStops(-23.5505, -46.6333);
      expect(stops, everyElement(isA<BusStop>()));
    });

    test('getNearbyStops should return exactly 4 mock stops', () async {
      final stops = await repository.getNearbyStops(-23.5505, -46.6333);
      expect(stops.length, 4);
    });

    test('all stops should have non-empty names', () async {
      final stops = await repository.getNearbyStops(-23.5505, -46.6333);
      for (final stop in stops) {
        expect(stop.name, isNotEmpty);
      }
    });

    test('all stops should have valid coordinates', () async {
      final stops = await repository.getNearbyStops(-23.5505, -46.6333);
      for (final stop in stops) {
        expect(stop.latitude, isA<double>());
        expect(stop.longitude, isA<double>());
      }
    });
  });
}
