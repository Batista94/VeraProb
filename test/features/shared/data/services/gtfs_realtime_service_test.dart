import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:busflow/features/shared/data/services/gtfs_realtime_service.dart';
import 'package:busflow/features/shared/data/repositories/vehicle_repository.dart';
import 'package:busflow/features/shared/domain/entities/vehicle_position.dart';

void main() {
  group('GtfsRealtimeService', () {
    late GtfsRealtimeService service;

    setUp(() {
      service = GtfsRealtimeService();
    });

    test('implements IVehiclePositionService', () {
      expect(service, isA<IVehiclePositionService>());
    });

    test('sendVehiclePosition throws UnimplementedError (read-only)', () {
      final pos = VehiclePosition(
        tripId: 'test',
        latitude: -23.55,
        longitude: -46.63,
        timestamp: DateTime.now(),
        source: 'api_public',
      );

      expect(
        () => service.sendVehiclePosition(pos),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('getVehiclePositions returns a Stream', () {
      final stream = service.getVehiclePositions();
      expect(stream, isA<Stream<List<VehiclePosition>>>());
    });

    test('getVehiclePositions emits mock positions after 5 seconds', () {
      fakeAsync((async) {
        final service = GtfsRealtimeService();
        final stream = service.getVehiclePositions();

        List<VehiclePosition>? received;
        final sub = stream.listen((positions) {
          received = positions;
        });

        // Advance time past the 5-second delay
        async.elapse(const Duration(seconds: 6));

        expect(received, isNotNull);
        expect(received!.length, 5);

        // Verify position properties
        for (final pos in received!) {
          expect(pos.tripId, contains('809U-10-TRIP'));
          expect(pos.source, 'api_public');
          expect(pos.latitude, isNotNull);
          expect(pos.longitude, isNotNull);
          expect(pos.speed, isNotNull);
          expect(pos.heading, isNotNull);
        }

        sub.cancel();
      });
    });

    test('mock positions have valid route names from destinations', () {
      fakeAsync((async) {
        final service = GtfsRealtimeService();
        final stream = service.getVehiclePositions();

        List<VehiclePosition>? received;
        final sub = stream.listen((positions) {
          received = positions;
        });

        async.elapse(const Duration(seconds: 6));

        expect(received, isNotNull);

        // Verify route names come from the destinations list
        final validDestinations = [
          'Term. Lapa',
          'Metro Santana',
          'Paulista',
          'Pinheiros',
          'Ibirapuera',
        ];
        for (final pos in received!) {
          expect(validDestinations, contains(pos.routeName));
        }

        sub.cancel();
      });
    });

    test('positions are near São Paulo center coordinates', () {
      fakeAsync((async) {
        final service = GtfsRealtimeService();
        final stream = service.getVehiclePositions();

        List<VehiclePosition>? received;
        final sub = stream.listen((positions) {
          received = positions;
        });

        async.elapse(const Duration(seconds: 6));

        expect(received, isNotNull);
        for (final pos in received!) {
          // SP center is approx -23.55, -46.63
          expect(pos.latitude, closeTo(-23.5505, 0.01));
          expect(pos.longitude, closeTo(-46.6333, 0.01));
        }

        sub.cancel();
      });
    });
  });
}
