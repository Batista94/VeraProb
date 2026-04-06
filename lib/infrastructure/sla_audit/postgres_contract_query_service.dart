import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/sla_audit/projections/contract_detail_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service.dart';
import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';

/// Postgres implementation of [ContractQueryService].
///
/// Derives read models from the `contracts`, `plan_declarations`, and
/// `execution_states` tables using targeted queries.
/// Purely read-only — never mutates state.
class PostgresContractQueryService implements ContractQueryService {
  final SupabaseClient _client;
  final SlaExecutionQueryService _slaExecutionQueryService;

  PostgresContractQueryService({
    SupabaseClient? client,
    required SlaExecutionQueryService slaExecutionQueryService,
  }) : _client = client ?? supabase,
       _slaExecutionQueryService = slaExecutionQueryService;

  @override
  Future<List<ContractSummaryView>> listContracts({
    required String organizationId,
    ContractStatusView? status,
  }) async {
    var query = _client
        .from('contracts')
        .select()
        .eq('organization_id', organizationId);

    if (status != null) {
      query = query.eq('status', status.name);
    }

    final List<dynamic> rows = await query.order(
      'created_at_utc',
      ascending: false,
    );

    final views = <ContractSummaryView>[];
    for (final row in rows) {
      final contractId = row['id'] as String;
      final summary = await _buildSummary(contractId, organizationId, row);
      views.add(summary);
    }
    return views;
  }

  @override
  Future<ContractDetailView?> getContractDetail({
    required String organizationId,
    required String contractId,
  }) async {
    final row = await _client
        .from('contracts')
        .select()
        .eq('organization_id', organizationId)
        .eq('id', contractId)
        .maybeSingle();

    if (row == null) return null;

    final summary = await _buildSummary(contractId, organizationId, row);

    // Recent executions — all SETs for this contract, ordered by windowStart desc
    final List<dynamic> stateRows = await _client
        .from('execution_states')
        .select()
        .eq('organization_id', organizationId)
        .eq('contract_id', contractId)
        .order('window_start_utc', ascending: false)
        .limit(200);

    var recentExecutions = stateRows.map((s) {
      final statusStr = s['status'] as String;
      return SlaExecutionItemView(
        setId: s['set_id'] as String,
        contractId: s['contract_id'] as String,
        status: ExecutionStatus.values.byName(statusStr),
        windowStartUtc: DateTime.parse(s['window_start_utc'] as String).toUtc(),
        windowEndUtc: DateTime.parse(s['window_end_utc'] as String).toUtc(),
        plannedVehicleId: s['planned_vehicle_id'] as String?,
        boundVehicleId: s['bound_vehicle_id'] as String?,
        boundAtUtc: s['binding_timestamp_utc'] != null
            ? DateTime.parse(s['binding_timestamp_utc'] as String).toUtc()
            : null,
        startLatitude: (s['start_latitude'] as num).toDouble(),
        startLongitude: (s['start_longitude'] as num).toDouble(),
        startRadiusMeters: (s['start_radius_meters'] as num).toInt(),
        contractualValue: (s['contractual_value_cents'] as num).toInt(),
        noShowPenaltyBps: (s['no_show_penalty_multiplier'] as num).toInt(),
      );
    }).toList();

    // Merge projected SETs from contractual_service_executions.
    // These are visible immediately after plan declaration, before any telemetry
    // arrives. SETs already present in execution_states are skipped (already merged).
    final List<dynamic> planIdRows = await _client
        .from('plan_declarations')
        .select('id')
        .eq('organization_id', organizationId)
        .eq('contract_id', contractId);

    final planIds = planIdRows.map((r) => r['id'] as String).toList();

    if (planIds.isNotEmpty) {
      final evaluatedSetIds = recentExecutions.map((e) => e.setId).toSet();

      final List<dynamic> projectedRows = await _client
          .from('contractual_service_executions')
          .select()
          .inFilter('plan_declaration_id', planIds)
          .order('scheduled_start_time_utc', ascending: true)
          .limit(500);

      final projected = projectedRows
          .where((s) => !evaluatedSetIds.contains(s['set_id'] as String))
          .map(
            (s) => SlaExecutionItemView(
              setId: s['set_id'] as String,
              contractId: contractId,
              status: ExecutionStatus.pending,
              windowStartUtc: DateTime.parse(
                s['scheduled_start_time_utc'] as String,
              ).toUtc(),
              windowEndUtc: DateTime.parse(
                s['scheduled_end_time_utc'] as String,
              ).toUtc(),
              plannedVehicleId: s['planned_vehicle_id'] as String?,
              boundVehicleId: null,
              boundAtUtc: null,
              startLatitude: (s['start_latitude'] as num).toDouble(),
              startLongitude: (s['start_longitude'] as num).toDouble(),
              startRadiusMeters: (s['start_radius_meters'] as num).toInt(),
              contractualValue: (s['contractual_value_cents'] as num).toInt(),
              noShowPenaltyBps: (s['no_show_penalty_multiplier'] as num).toInt(),
            ),
          )
          .toList();

      if (projected.isNotEmpty) {
        final merged = [...recentExecutions, ...projected];
        merged.sort((a, b) => b.windowStartUtc.compareTo(a.windowStartUtc));
        recentExecutions = merged;
      }
    }

    // Financial summary
    final financialSummary = await _slaExecutionQueryService.getSummary(
      organizationId: organizationId,
      contractId: contractId,
    );

    return ContractDetailView(
      summary: summary,
      recentExecutions: recentExecutions,
      financialSummary: financialSummary,
    );
  }

  // ── Private helpers ────────────────────────────────────────

  Future<ContractSummaryView> _buildSummary(
    String contractId,
    String organizationId,
    Map<String, dynamic> row,
  ) async {
    // Plan counters
    final List<dynamic> planRows = await _client
        .from('plan_declarations')
        .select('plan_version')
        .eq('organization_id', organizationId)
        .eq('contract_id', contractId)
        .order('plan_version', ascending: false);

    final planCount = planRows.length;
    final activePlanVersion = planRows.isEmpty
        ? 0
        : (planRows.first['plan_version'] as int);

    // Execution state counters (single query — aggregate in Dart to avoid RPC)
    final List<dynamic> stateRows = await _client
        .from('execution_states')
        .select('status')
        .eq('organization_id', organizationId)
        .eq('contract_id', contractId);

    final totalSets = stateRows.length;
    int pendingCount = 0;
    int executedCount = 0;

    for (final s in stateRows) {
      final st = s['status'] as String;
      if (st == ExecutionStatus.pending.name) pendingCount++;
      if (st == ExecutionStatus.executed.name) executedCount++;
    }

    final slaHealthBps = totalSets == 0
        ? 0
        : (executedCount * 10000 ~/ totalSets);

    return ContractSummaryView(
      id: row['id'] as String,
      name: row['name'] as String,
      contractorName: row['contractor_name'] as String,
      status: ContractStatusView.values.byName(row['status'] as String),
      validFromUtc: DateTime.parse(row['valid_from_utc'] as String).toUtc(),
      validUntilUtc: DateTime.parse(row['valid_until_utc'] as String).toUtc(),
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
      activatedAtUtc: row['activated_at_utc'] != null
          ? DateTime.parse(row['activated_at_utc'] as String).toUtc()
          : null,
      planCount: planCount,
      activePlanVersion: activePlanVersion,
      totalSetsInProgress: pendingCount,
      slaHealthBps: slaHealthBps,
      financialCeilingCents: (row['financial_ceiling_cents'] as num?)?.toInt(),
    );
  }
}
