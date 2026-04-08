import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// Postgres implementation for [SlaExecutionQueryService].
/// Extracts flat DTOs directly from the `execution_states` table.
/// Purely read-only, strict separation from Domain.
class SlaExecutionQueryServicePostgres implements SlaExecutionQueryService {
  final SupabaseClient _client;
  final IDateTimeProvider _dateTimeProvider;

  SlaExecutionQueryServicePostgres(this._client, this._dateTimeProvider);

  @override
  Future<SlaExecutionSummary> getSummary({
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('execution_states')
        .select('status, contractual_value_cents, no_show_penalty_multiplier')
        .eq('organization_id', organizationId);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    final rows = await query.order('created_at_utc', ascending: false);

    int pending = 0;
    int executed = 0;
    int noShow = 0;
    int evidenceGap = 0;

    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    for (var row in rows) {
      final statusStr = row['status'] as String;
      final val = Money((row['contractual_value_cents'] as num).toInt());
      final int penaltyBps = (row['no_show_penalty_multiplier'] as num).toInt();

      if (statusStr == ExecutionStatus.pending.name) {
        pending++;
        revenueAtRisk = revenueAtRisk + val;
      } else if (statusStr == ExecutionStatus.executed.name) {
        executed++;
        protectedRevenue = protectedRevenue + val;
      } else if (statusStr == ExecutionStatus.noShow.name) {
        noShow++;
        lostRevenue = lostRevenue + val.multiplyByBps(penaltyBps);
      } else if (statusStr == ExecutionStatus.evidenceGap.name) {
        evidenceGap++;
        lostRevenue = lostRevenue + val;
      }
    }

    return SlaExecutionSummary(
      contractId: contractId,
      totalPending: pending,
      totalExecuted: executed,
      totalNoShow: noShow,
      totalEvidenceGap: evidenceGap,
      generatedAtUtc: _dateTimeProvider.now(),
      protectedRevenue: protectedRevenue.cents,
      revenueAtRisk: revenueAtRisk.cents,
      lostRevenue: lostRevenue.cents,
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
        contractualValue: (row['contractual_value_cents'] as num).toInt(),
        noShowPenaltyBps: (row['no_show_penalty_multiplier'] as num).toInt(),
      );
    }).toList();
  }

  @override
  Future<SlaExecutionItemView?> findBySetId(
    String setId, {
    required String organizationId,
  }) async {
    final row = await _client
        .from('execution_states')
        .select()
        .eq('organization_id', organizationId)
        .eq('set_id', setId)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;

    return SlaExecutionItemView(
      setId: row['set_id'] as String,
      contractId: row['contract_id'] as String,
      status: ExecutionStatus.values.byName(row['status'] as String),
      windowStartUtc: DateTime.parse(row['window_start_utc'] as String).toUtc(),
      windowEndUtc: DateTime.parse(row['window_end_utc'] as String).toUtc(),
      plannedVehicleId: row['planned_vehicle_id'] as String?,
      boundVehicleId: row['bound_vehicle_id'] as String?,
      boundAtUtc: row['binding_timestamp_utc'] != null
          ? DateTime.parse(row['binding_timestamp_utc'] as String).toUtc()
          : null,
      startLatitude: (row['start_latitude'] as num).toDouble(),
      startLongitude: (row['start_longitude'] as num).toDouble(),
      startRadiusMeters: (row['start_radius_meters'] as num).toInt(),
      contractualValue: (row['contractual_value_cents'] as num).toInt(),
      noShowPenaltyBps: (row['no_show_penalty_multiplier'] as num).toInt(),
    );
  }

  @override
  Future<List<SlaExecutionItemView>> listByWindow(
    DateTime startUtc,
    DateTime endUtc, {
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('execution_states')
        .select()
        .eq('organization_id', organizationId)
        .gte('window_start_utc', startUtc.toUtc().toIso8601String())
        .lt('window_start_utc', endUtc.toUtc().toIso8601String());

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    final rows = await query
        .order('window_start_utc', ascending: true)
        .limit(500);

    return rows.map((row) {
      return SlaExecutionItemView(
        setId: row['set_id'] as String,
        contractId: row['contract_id'] as String,
        status: ExecutionStatus.values.byName(row['status'] as String),
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
        contractualValue: (row['contractual_value_cents'] as num).toInt(),
        noShowPenaltyBps: (row['no_show_penalty_multiplier'] as num).toInt(),
      );
    }).toList();
  }
}
