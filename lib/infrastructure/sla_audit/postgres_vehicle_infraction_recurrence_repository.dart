import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_repository.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Postgres implementation of [VehicleInfractionRecurrenceRepository].
///
/// Queries `sanction_review_queue` using the denormalized [vehicle_plate]
/// column (added via migration 20260610000001_srq_vehicle_plate.sql).
///
/// INV-1: All queries filter by [organizationId].
/// INV-9: Month boundaries computed in UTC.
class PostgresVehicleInfractionRecurrenceRepository
    implements VehicleInfractionRecurrenceRepository {
  final SupabaseClient _client;

  PostgresVehicleInfractionRecurrenceRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<List<SanctionReviewQueueEntry>> findByPlateInMonth({
    required String organizationId,
    required String vehiclePlate,
    required DateTime referenceUtc,
    required String excludeQueueEntryId,
  }) async {
    final monthStart = DateTime.utc(referenceUtc.year, referenceUtc.month, 1);
    final monthEnd = DateTime.utc(referenceUtc.year, referenceUtc.month + 1, 1);

    final response = await _client
        .from('sanction_review_queue')
        .select()
        .eq('organization_id', organizationId)
        .eq('vehicle_plate', vehiclePlate)
        .gte('created_at', monthStart.toIso8601String())
        .lt('created_at', monthEnd.toIso8601String())
        .neq('id', excludeQueueEntryId)
        .order('created_at', ascending: true)
        .limit(100);

    return (response as List)
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList();
  }

  static SanctionReviewQueueEntry _fromRow(Map<String, dynamic> row) {
    return SanctionReviewQueueEntry(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      ledgerEntryId: row['ledger_entry_id'] as String,
      setId: row['set_id'] as String,
      contractId: row['contract_id'] as String,
      vehiclePlate: row['vehicle_plate'] as String?,
      verdictEvidence: VerdictEvidence.fromJson(
        row['verdict_evidence'] as Map<String, dynamic>,
      ),
      status: IntegrityException.shield(
        SanctionReviewStatus.values,
        row['status'] as String,
        'status',
      ),
      createdAtUtc: DateTime.parse(row['created_at'] as String).toUtc(),
      reviewedAtUtc: row['reviewed_at'] != null
          ? DateTime.parse(row['reviewed_at'] as String).toUtc()
          : null,
      reviewedByUserId: row['reviewed_by'] as String?,
      rejectionReason: row['rejection_reason'] as String?,
    );
  }
}
