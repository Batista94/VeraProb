import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_repository.dart';

/// In-memory stub of [VehicleInfractionRecurrenceRepository].
///
/// Always returns an empty list. Unit tests inject a
/// `_FakeVehicleInfractionRecurrenceRepository` directly — this stub exists
/// only to satisfy the [PersistenceMode.inMemory] switch in
/// `sla_persistence_provider.dart`.
class InMemoryVehicleInfractionRecurrenceRepository
    implements VehicleInfractionRecurrenceRepository {
  const InMemoryVehicleInfractionRecurrenceRepository();

  @override
  Future<List<SanctionReviewQueueEntry>> findByPlateInMonth({
    required String organizationId,
    required String vehiclePlate,
    required DateTime referenceUtc,
    required String excludeQueueEntryId,
  }) async => const [];
}
