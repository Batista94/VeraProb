import 'package:veraprob/domain/entities/stop.dart';
import 'package:veraprob/domain/stops/i_stop_repository.dart';

/// Concrete implementation of [IStopRepository].
///
/// Currently returns mock data; replace with Supabase query when
/// the `stops` table is available in the schema.
class StopRepository implements IStopRepository {
  @override
  Future<List<Stop>> getNearbyStops(double lat, double lon) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    return [
      const Stop(
        id: '1',
        name: 'Pça. da Sé - Sé',
        latitude: -23.5500, // Physical Metric - Double Required
        longitude: -46.6330, // Physical Metric - Double Required
      ),
      const Stop(
        id: '2',
        name: 'Terminal Pq. Dom Pedro II',
        latitude: -23.5470, // Physical Metric - Double Required
        longitude: -46.6280, // Physical Metric - Double Required
      ),
      const Stop(
        id: '3',
        name: 'Av. Paulista, 1500 (MASP)',
        latitude: -23.5615, // Physical Metric - Double Required
        longitude: -46.6559, // Physical Metric - Double Required
      ),
      const Stop(
        id: '4',
        name: 'Metrô Consolação',
        latitude: -23.5580, // Physical Metric - Double Required
        longitude: -46.6600, // Physical Metric - Double Required
      ),
    ];
  }
}
