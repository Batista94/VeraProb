import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/shared/domain/entities/vehicle_position.dart';

void main() {
  group('VehiclePosition Entity', () {
    test('should instantiate correctly', () {
      final now = DateTime.now();
      final pos = VehiclePosition(
        tripId: '1234',
        latitude: -23.55,
        longitude: -46.63,
        timestamp: now,
        source: 'api_public',
        routeName: '809U',
        speed: 10.0,
      );

      expect(pos.tripId, '1234');
      expect(pos.latitude, -23.55);
      expect(pos.longitude, -46.63);
      expect(pos.timestamp, now);
      expect(pos.source, 'api_public');
      expect(pos.routeName, '809U');
      expect(pos.speed, 10.0);
    });
  });
}
