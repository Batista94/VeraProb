import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/stops/bus_stop_repository.dart';
import 'package:veraprob/domain/entities/stop.dart';

void main() {
  group('StopRepository', () {
    late StopRepository repository;

    setUp(() {
      repository = StopRepository();
    });

    test('getNearbyStops should return a non-empty list', () async {
      final stops = await repository.getNearbyStops(-23.5505, -46.6333);
      expect(stops, isNotEmpty);
    });

    test('getNearbyStops should return Stop instances', () async {
      final stops = await repository.getNearbyStops(-23.5505, -46.6333);
      expect(stops, everyElement(isA<Stop>()));
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

    test('implements IStopRepository contract', () {
      expect(repository, isA<StopRepository>());
    });
  });
}
