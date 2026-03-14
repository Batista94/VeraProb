import 'dart:async';
import 'dart:math';
import '../../domain/entities/vehicle_position.dart';
import '../repositories/vehicle_repository.dart';

class GtfsRealtimeService implements IVehiclePositionService {
  // Simulating an API endpoint
  // ignore: unused_field
  final String _apiUrl = 'https://api.olhovivo.sptrans.com.br/v2.1';
  // ignore: unused_field
  final String _token = 'YOUR_API_TOKEN';

  @override
  Stream<List<VehiclePosition>> getVehiclePositions() async* {
    // In a real implementation, we would poll the API periodically
    // For MVP, we simulate a stream of updates every 5 seconds

    while (true) {
      await Future.delayed(const Duration(seconds: 5));

      // Simulate fetching data from API
      final positions = _generateMockPositions();
      yield positions;
    }
  }

  List<VehiclePosition> _generateMockPositions() {
    // Generate some random bus positions around São Paulo center
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
        tripId: '809U-10-TRIP-$index', // Make it look more real
        latitude: -23.550520 + (random.nextDouble() * 0.01 - 0.005),
        longitude: -46.633308 + (random.nextDouble() * 0.01 - 0.005),
        speed: random.nextDouble() * 60,
        heading: random.nextDouble() * 360,
        timestamp: DateTime.now().toUtc(),
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
