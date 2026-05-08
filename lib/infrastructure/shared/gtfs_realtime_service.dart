import 'dart:async';
import 'dart:math';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'vehicle_repository.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

class GtfsRealtimeService implements IVehiclePositionService {
  // ignore: unused_field
  final String _apiUrl = 'https://api.olhovivo.sptrans.com.br/v2.1';
  // ignore: unused_field
  final String _token = 'YOUR_API_TOKEN';
  final IDateTimeProvider _dateTimeProvider;

  GtfsRealtimeService(this._dateTimeProvider);

  @override
  Stream<List<VehiclePosition>> getVehiclePositions() async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 5));

      final positions = _generateMockPositions();
      yield positions;
    }
  }

  List<VehiclePosition> _generateMockPositions() {
    final random = Random();
    final destinations = [
      'Term. Lapa',
      'Metro Santana',
      'Paulista',
      'Pinheiros',
      'Ibirapuera',
    ];

    return List.generate(5, (index) {
      final dest = destinations[index % destinations.length];
      return VehiclePosition(
        tripId: '809U-10-TRIP-$index',
        latitude: -23.550520 + (random.nextDouble() * 0.01 - 0.005),
        longitude: -46.633308 + (random.nextDouble() * 0.01 - 0.005),
        speed: random.nextDouble() * 60,
        heading: random.nextDouble() * 360,
        timestamp: _dateTimeProvider.nowUtc(),
        source: 'api_public',
        routeName: dest,
      );
    });
  }

  @override
  Future<void> sendVehiclePosition(VehiclePosition position) {
    throw UnimplementedError('GTFS Service is read-only');
  }
}
