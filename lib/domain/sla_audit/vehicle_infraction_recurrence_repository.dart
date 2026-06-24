import 'sanction_review_queue_entry.dart';

/// Repository interface for vehicle infraction recurrence queries.
///
/// Implementations query the `sanction_review_queue` table, which carries a
/// denormalized [vehicle_plate] column (populated by the DB trigger at INSERT
/// time — see migration 20260610000001_srq_vehicle_plate.sql).
///
/// INV-18: Pure Dart interface — no Supabase/Flutter imports.
/// INV-9: [referenceUtc] MUST be UTC.
abstract class VehicleInfractionRecurrenceRepository {
  /// Returns all sanction queue entries for [vehiclePlate] within the same
  /// calendar month as [referenceUtc], excluding the entry identified by
  /// [excludeQueueEntryId] (the current infraction being reviewed).
  ///
  /// Results are ordered ascending by `created_at`.
  ///
  /// INV-1: Implementations MUST filter by [organizationId].
  /// INV-9: [beforeUtc] MUST be UTC. Only entries with `created_at < beforeUtc`
  /// are returned — callers pass the current card's own `createdAtUtc` so that
  /// future cards in the same month do not inflate the sequence number.
  Future<List<SanctionReviewQueueEntry>> findByPlateInMonth({
    required String organizationId,
    required String vehiclePlate,
    required DateTime referenceUtc,
    required String excludeQueueEntryId,
    required DateTime beforeUtc,
  });
}
