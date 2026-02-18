import '../../domain/entities/bus_stop.dart';

class BusStopRepository {
  Future<List<BusStop>> getNearbyStops(double lat, double lon) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock data: explicit stops near São Paulo center
    return [
      BusStop(
        id: '1',
        name: 'Pça. da Sé - Sé',
        latitude: -23.5500,
        longitude: -46.6330,
        code: '1001',
      ),
      BusStop(
        id: '2',
        name: 'Terminal Pq. Dom Pedro II',
        latitude: -23.5470,
        longitude: -46.6280,
        code: '2002',
      ),
      BusStop(
        id: '3',
        name: 'Av. Paulista, 1500 (MASP)',
        latitude: -23.5615,
        longitude: -46.6559,
        code: '3003',
      ),
      BusStop(
        id: '4',
        name: 'Metrô Consolação',
        latitude: -23.5580,
        longitude: -46.6600,
        code: '4004',
      ),
    ];
  }
}
