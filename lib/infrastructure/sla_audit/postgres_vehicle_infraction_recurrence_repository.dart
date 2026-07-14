import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_review_queue_repository.dart';

/// Postgres implementation of [VehicleInfractionRecurrenceRepository].
///
/// Queries `sanction_review_queue` using the denormalized [vehicle_plate]
/// column (added via migration 20260610000001_srq_vehicle_plate.sql).
///
/// INV-1: All queries filter by [organizationId].
/// INV-9: Month boundaries computed in UTC.
class PostgresVehicleInfractionRecurrenceRepository
    extends BasePostgresRepository
    implements VehicleInfractionRecurrenceRepository {
  PostgresVehicleInfractionRecurrenceRepository(super.client);

  @override
  Future<List<SanctionReviewQueueEntry>> findByPlateInMonth({
    required String organizationId,
    required String vehiclePlate,
    required DateTime referenceUtc,
    required String excludeQueueEntryId,
    required DateTime beforeUtc,
  }) async {
    try {
      final monthStart = DateTime.utc(referenceUtc.year, referenceUtc.month, 1);
      final monthEnd = DateTime.utc(
        referenceUtc.year,
        referenceUtc.month + 1,
        1,
      );

      final response = await client
          .from('sanction_review_queue')
          .select()
          .eq('organization_id', organizationId)
          .eq('vehicle_plate', vehiclePlate)
          .gte('created_at', monthStart.toIso8601String())
          .lt('created_at', monthEnd.toIso8601String())
          .lt('created_at', beforeUtc.toIso8601String())
          .neq('id', excludeQueueEntryId)
          .order('created_at', ascending: true)
          .limit(100);

      return (response as List)
          .map(
            (row) => PostgresSanctionReviewQueueRepository.fromRow(
              row as Map<String, dynamic>,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'vehicle_infraction',
      );
    }
  }
}
