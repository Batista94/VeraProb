import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/bus_stop.dart';

void main() {
  group('BusStop Entity', () {
    const stop = BusStop(
      id: '1',
      name: 'Pça. da Sé',
      latitude: -23.55,
      longitude: -46.63,
      code: '1001',
    );

    const stopNoCode = BusStop(
      id: '2',
      name: 'Terminal Teste',
      latitude: -23.56,
      longitude: -46.64,
    );

    test('should instantiate with all properties', () {
      expect(stop.id, '1');
      expect(stop.name, 'Pça. da Sé');
      expect(stop.latitude, -23.55);
      expect(stop.longitude, -46.63);
      expect(stop.code, '1001');
    });

    test('code should be nullable and default to null', () {
      expect(stopNoCode.code, isNull);
    });

    test('should store correct geographic coordinates', () {
      expect(stop.latitude, lessThan(0)); // Southern hemisphere
      expect(stop.longitude, lessThan(0)); // Western hemisphere
    });
  });
}
