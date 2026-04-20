import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/adapters/simulation_data_provider.dart';
import 'package:veraprob/data/services/fleet_simulation_service.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

/// Subclass that overrides only positionStream to return a controlled stream.
class FakeFleetSimulationService extends FleetSimulationService {
  final _controller = StreamController<List<VehiclePosition>>.broadcast();

  FakeFleetSimulationService() : super();

  void emit(List<VehiclePosition> positions) => _controller.add(positions);

  Future<void> close() => _controller.close();

  @override
  Stream<List<VehiclePosition>> positionStream({
    Duration interval = const Duration(seconds: 15),
  }) async* {
    yield* _controller.stream;
  }
}

VehiclePosition makePosition(String tripId) => VehiclePosition(
  id: tripId,
  tripId: tripId,
  latitude: -23.5,
  longitude: -46.6,
  timestamp: DateTime.now().toUtc(),
  source: 'sim',
);

void main() {
  group('SimulationDataProvider', () {
    late FakeFleetSimulationService fakeService;
    late SimulationDataProvider provider;

    setUp(() {
      fakeService = FakeFleetSimulationService();
      provider = SimulationDataProvider(fakeService);
    });

    tearDown(() async {
      await provider.disconnect();
      await fakeService.close();
    });

    test('isConnected is false before connect()', () {
      expect(provider.isConnected, isFalse);
    });

    test('isConnected is true after connect()', () async {
      await provider.connect();
      expect(provider.isConnected, isTrue);
    });

    test(
      'positionStream forwards emissions from FleetSimulationService',
      () async {
        await provider.connect();

        final positions = <List<VehiclePosition>>[];
        final sub = provider.positionStream.listen(positions.add);

        final batch = [makePosition('trip-1')];
        fakeService.emit(batch);
        await Future.delayed(Duration.zero);

        expect(positions, hasLength(1));
        expect(positions.first, batch);
        await sub.cancel();
      },
    );

    test('connect() is idempotent — calling twice does not throw', () async {
      await provider.connect();
      await provider.connect(); // second call is a no-op
      expect(provider.isConnected, isTrue);
    });

    test('disconnect() sets isConnected to false', () async {
      await provider.connect();
      await provider.disconnect();
      expect(provider.isConnected, isFalse);
    });

    test('disconnect() when not connected is safe (no throw)', () async {
      await provider.disconnect();
      expect(provider.isConnected, isFalse);
    });
  });
}
