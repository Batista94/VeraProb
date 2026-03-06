import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/sla_audit/execution_status.dart';
import '../../application/sla_audit/projections/sla_execution_item_view.dart';
import '../../application/sla_audit/projections/sla_execution_query_service.dart';
import '../../application/sla_audit/projections/sla_execution_summary.dart';

/// Postgres implementation for [SlaExecutionQueryService].
/// Extracts flat DTOs directly from the `execution_states` table.
/// Purely read-only, strict separation from Domain.
class SlaExecutionQueryServicePostgres implements SlaExecutionQueryService {
  final SupabaseClient _client;

  SlaExecutionQueryServicePostgres(this._client);

  @override
  Future<SlaExecutionSummary> getSummary({
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('execution_states')
        .select('status, contractual_value, no_show_penalty_multiplier')
        .eq('organization_id', organizationId);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    final rows = await query.order('created_at_utc', ascending: false);

    int pending = 0;
    int executed = 0;
    int noShow = 0;
    int evidenceGap = 0;

    double protectedRevenue = 0.0;
    double revenueAtRisk = 0.0;
    double lostRevenue = 0.0;

    for (var row in rows) {
      final statusStr = row['status'] as String;
      final val = (row['contractual_value'] as num).toDouble();
      final mult = (row['no_show_penalty_multiplier'] as num).toDouble();

      if (statusStr == ExecutionStatus.pending.name) {
        pending++;
        revenueAtRisk += val;
      } else if (statusStr == ExecutionStatus.executed.name) {
        executed++;
        protectedRevenue += val;
      } else if (statusStr == ExecutionStatus.noShow.name) {
        noShow++;
        lostRevenue += val * mult;
      } else if (statusStr == ExecutionStatus.evidenceGap.name) {
        evidenceGap++;
        lostRevenue += val;
      }
    }

    return SlaExecutionSummary(
      contractId: contractId,
      totalPending: pending,
      totalExecuted: executed,
      totalNoShow: noShow,
      totalEvidenceGap: evidenceGap,
      generatedAtUtc: DateTime.now().toUtc(),
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
    );
  }

  @override
  Future<List<SlaExecutionItemView>> listByStatus(
    ExecutionStatus status, {
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('execution_states')
        .select()
        .eq('organization_id', organizationId)
        .eq('status', status.name);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    // Limit applied to prevent full ledger scanning into memory
    final rows = await query
        .order('window_start_utc', ascending: true)
        .limit(500);

    return rows.map((row) {
      return SlaExecutionItemView(
        setId: row['set_id'] as String,
        contractId: row['contract_id'] as String,
        status: status,
        windowStartUtc: DateTime.parse(
          row['window_start_utc'] as String,
        ).toUtc(),
        windowEndUtc: DateTime.parse(row['window_end_utc'] as String).toUtc(),
        plannedVehicleId: row['planned_vehicle_id'] as String?,
        boundVehicleId: row['bound_vehicle_id'] as String?,
        boundAtUtc: row['binding_timestamp_utc'] != null
            ? DateTime.parse(row['binding_timestamp_utc'] as String).toUtc()
            : null,
        startLatitude: (row['start_latitude'] as num).toDouble(),
        startLongitude: (row['start_longitude'] as num).toDouble(),
        startRadiusMeters: (row['start_radius_meters'] as num).toInt(),
        contractualValue: (row['contractual_value'] as num).toDouble(),
        noShowPenaltyMultiplier: (row['no_show_penalty_multiplier'] as num)
            .toDouble(),
      );
    }).toList();
  }
}
