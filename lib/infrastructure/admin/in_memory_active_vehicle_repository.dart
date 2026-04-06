import 'package:veraprob/domain/admin/i_active_vehicle_repository.dart';

/// In-memory implementation of [IActiveVehicleRepository] for use in tests.
///
/// Accepts a pre-configured count map so tests can control vehicle availability
/// without spinning up a database.
///
/// Example:
/// ```dart
/// // No active vehicles:
/// InMemoryActiveVehicleRepository()
///
/// // 2 active vehicles for a specific org:
/// InMemoryActiveVehicleRepository(countsByOrg: {'org-uuid': 2})
/// ```
class InMemoryActiveVehicleRepository implements IActiveVehicleRepository {
  final Map<String, int> _countsByOrg;

  const InMemoryActiveVehicleRepository({
    Map<String, int> countsByOrg = const {},
  }) : _countsByOrg = countsByOrg;

  @override
  Future<int> countActiveByOrganization(String organizationId) async =>
      _countsByOrg[organizationId] ?? 0;
}
