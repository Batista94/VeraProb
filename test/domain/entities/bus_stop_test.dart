import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/stop.dart';

void main() {
  group('Stop Entity', () {
    const stop = Stop(
      id: '1',
      name: 'Pça. da Sé',
      latitude: -23.55,
      longitude: -46.63,
    );

    const stopWithGtfs = Stop(
      id: '2',
      name: 'Terminal Teste',
      latitude: -23.56,
      longitude: -46.64,
      gtfsStopId: 'gtfs-002',
    );

    test('should instantiate with required properties', () {
      expect(stop.id, '1');
      expect(stop.name, 'Pça. da Sé');
      expect(stop.latitude, -23.55);
      expect(stop.longitude, -46.63);
    });

    test('gtfsStopId should be nullable and default to null', () {
      expect(stop.gtfsStopId, isNull);
    });

    test('should store gtfsStopId when provided', () {
      expect(stopWithGtfs.gtfsStopId, 'gtfs-002');
    });

    test('should store correct geographic coordinates', () {
      expect(stop.latitude, lessThan(0)); // Southern hemisphere
      expect(stop.longitude, lessThan(0)); // Western hemisphere
    });

    test('equality is value-based via Equatable', () {
      const duplicate = Stop(
        id: '1',
        name: 'Pça. da Sé',
        latitude: -23.55,
        longitude: -46.63,
      );
      expect(stop, equals(duplicate));
    });
  });
}
