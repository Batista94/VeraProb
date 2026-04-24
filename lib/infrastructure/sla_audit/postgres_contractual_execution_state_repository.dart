import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Postgres implementation of [ContractualExecutionStateRepository].
///
/// Implements a dual-table model: Current State + Append-Only Transition History.
///
/// **Causal Linkage**: Creation is only allowed if the SET exists in
/// `contractual_service_executions`.
///
/// **Audit Trail**: Every relevant transition (status changes, finalized data)
/// is recorded in `execution_state_transitions`.
class PostgresContractualExecutionStateRepository
    with PostgresErrorInterceptor
    implements ContractualExecutionStateRepository {
  final SupabaseClient _client;
  final IDateTimeProvider _dateTimeProvider;

  PostgresContractualExecutionStateRepository(
    this._client,
    this._dateTimeProvider,
  );

  @override
  Future<void> save(ContractualExecutionState state) async {
    // 1. Ensure Causal Linkage (SET must exist AND belong to same tenant)
    try {
      final setExists = await _client
          .from('contractual_service_executions')
          .select('set_id')
          .eq('set_id', state.setId)
          .eq('organization_id', state.organizationId)
          .maybeSingle();

      if (setExists == null) {
        throw ResourceNotFoundException(
          resourceType: 'execution_state',
          resourceId: state.setId,
        );
      }
    } on ResourceNotFoundException {
      rethrow;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'execution_state',
        resourceId: state.setId,
      );
    }

    // 2. Resolve existing state if any
    try {
      final existingData = await _client
          .from('execution_states')
          .select()
          .eq('id', state.id)
          .maybeSingle();

      if (existingData == null) {
        // 3a. New Aggregate: Insert Current State and Initial Transition
        await _client.from('execution_states').insert(_mapToDb(state));
        await _recordTransition(state, null, 'Initial Creation');
      } else {
        // 3b. Existing Aggregate: Update and record transition if needed
        final previousStatus = _parseStatus(existingData['status']);
        final hasStatusChanged = previousStatus != state.status;

        // We also consider finalized timestamps or evaluation dates as relevant for audit
        final hasDataChanged =
            hasStatusChanged ||
            existingData['bound_vehicle_id'] != state.boundVehicleId ||
            existingData['finalized_at_utc'] !=
                state.finalizedAtUtc?.toIso8601String();

        if (hasDataChanged) {
          await _client
              .from('execution_states')
              .update(_mapToDb(state))
              .eq('id', state.id);

          await _recordTransition(
            state,
            previousStatus,
            hasStatusChanged ? 'Status Change' : 'Data Update',
          );
        } else {
          // Just update evaluation timestamp (non-auditable operational data)
          await _client
              .from('execution_states')
              .update({
                'last_evaluated_at_utc': state.lastEvaluatedAtUtc
                    .toIso8601String(),
              })
              .eq('id', state.id);
        }
      }
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'execution_state',
        resourceId: state.id,
      );
    }
  }

  @override
  Future<ContractualExecutionState?> findBySetId(String setId) async {
    try {
      final data = await _client
          .from('execution_states')
          .select()
          .eq('set_id', setId)
          .maybeSingle();

      if (data == null) return null;
      return _mapToEntity(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'execution_state',
        resourceId: setId,
      );
    }
  }

  @override
  Future<List<ContractualExecutionState>> findPlannedByContractAndTime(
    String contractId,
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    try {
      final now = nowUtc.toIso8601String();
      final List<dynamic> data = await _client
          .from('execution_states')
          .select()
          .eq('organization_id', organizationId)
          .eq('contract_id', contractId)
          .eq('status', ExecutionStatus.planned.name)
          .lte('window_start_utc', now)
          .gte('window_end_utc', now);

      return data.map((d) => _mapToEntity(d)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'execution_state',
        resourceId: contractId,
      );
    }
  }

  @override
  Future<List<ContractualExecutionState>> findPlannedInWindow(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    try {
      final now = nowUtc.toIso8601String();
      final List<dynamic> data = await _client
          .from('execution_states')
          .select()
          .eq('organization_id', organizationId)
          .eq('status', ExecutionStatus.planned.name)
          .lte('window_start_utc', now)
          .gte('window_end_utc', now);

      return data.map((d) => _mapToEntity(d)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'execution_state');
    }
  }

  @override
  Future<List<ContractualExecutionState>> findActiveInWindow(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    try {
      final now = nowUtc.toIso8601String();
      final List<dynamic> data = await _client
          .from('execution_states')
          .select()
          .eq('organization_id', organizationId)
          .filter(
            'status',
            'in',
            '(planned,inTransit,failed,completedWithGaps)',
          )
          .lte('window_start_utc', now)
          .gte('window_end_utc', now);

      return data.map((d) => _mapToEntity(d)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'execution_state');
    }
  }

  @override
  Future<List<ContractualExecutionState>> findExpiredPlanned(
    DateTime nowUtc, {
    required String organizationId,
  }) async {
    try {
      final now = nowUtc.toIso8601String();
      final List<dynamic> data = await _client
          .from('execution_states')
          .select()
          .eq('organization_id', organizationId)
          .inFilter('status', [
            ExecutionStatus.planned.name,
            ExecutionStatus.inTransit.name,
          ])
          .lt('window_end_utc', now);

      return data.map((d) => _mapToEntity(d)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'execution_state');
    }
  }

  @override
  Future<List<ContractualExecutionState>> findAll({
    required String organizationId,
  }) async {
    try {
      final List<dynamic> data = await _client
          .from('execution_states')
          .select()
          .eq('organization_id', organizationId);
      return data.map((d) => _mapToEntity(d)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'execution_state');
    }
  }

  @override
  Future<List<ContractualExecutionState>> findByContract(
    String contractId, {
    required String organizationId,
  }) async {
    try {
      final List<dynamic> data = await _client
          .from('execution_states')
          .select()
          .eq('organization_id', organizationId)
          .eq('contract_id', contractId);
      return data.map((d) => _mapToEntity(d)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'execution_state',
        resourceId: contractId,
      );
    }
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _recordTransition(
    ContractualExecutionState state,
    ExecutionStatus? previousStatus,
    String reason,
  ) async {
    await _client.from('execution_state_transitions').insert({
      'execution_state_id': state.id,
      'organization_id': state.organizationId,
      'previous_status': previousStatus?.name,
      'new_status': state.status.name,
      'transitioned_at_utc': _dateTimeProvider.nowUtc().toIso8601String(),
      'reason': reason,
      'metadata': {
        'last_evaluated_at_utc': state.lastEvaluatedAtUtc.toIso8601String(),
        'bound_vehicle_id': state.boundVehicleId,
        'finalized_at_utc': state.finalizedAtUtc?.toIso8601String(),
      },
    });
  }

  Map<String, dynamic> _mapToDb(ContractualExecutionState state) {
    return {
      'id': state.id,
      'organization_id': state.organizationId,
      'set_id': state.setId,
      'contract_id': state.contractId,
      'plan_version': state.planVersion,
      'start_latitude': state.startLatitude,
      'start_longitude': state.startLongitude,
      'start_radius_meters': state.startRadiusMeters,
      'planned_vehicle_id': state.plannedVehicleId,
      'contractual_value_cents': state.contractualValue.cents,
      'no_show_penalty_multiplier': state.noShowPenaltyBps,
      'window_start_utc': state.windowStartUtc.toIso8601String(),
      'window_end_utc': state.windowEndUtc.toIso8601String(),
      'status': state.status.name,
      'bound_vehicle_id': state.boundVehicleId,
      'binding_timestamp_utc': state.bindingTimestampUtc?.toIso8601String(),
      'binding_latitude': state.bindingLatitude,
      'binding_longitude': state.bindingLongitude,
      'created_at_utc': state.createdAtUtc.toIso8601String(),
      'last_evaluated_at_utc': state.lastEvaluatedAtUtc.toIso8601String(),
      'status_last_updated_at_utc': state.statusLastUpdatedAtUtc
          .toIso8601String(),
      'finalized_at_utc': state.finalizedAtUtc?.toIso8601String(),
    };
  }

  ContractualExecutionState _mapToEntity(Map<String, dynamic> data) {
    return ContractualExecutionState.reconstitute(
      id: data['id'] as String,
      organizationId: data['organization_id'] as String,
      setId: data['set_id'] as String,
      contractId: data['contract_id'] as String,
      planVersion: data['plan_version'] as int,
      startLatitude: (data['start_latitude'] as num).toDouble(),
      startLongitude: (data['start_longitude'] as num).toDouble(),
      startRadiusMeters: data['start_radius_meters'] as int,
      plannedVehicleId: data['planned_vehicle_id'] as String?,
      contractualValue: Money((data['contractual_value_cents'] as num).toInt()),
      noShowPenaltyBps: (data['no_show_penalty_multiplier'] as num).toInt(),
      windowStartUtc: DateTime.parse(data['window_start_utc'] as String),
      windowEndUtc: DateTime.parse(data['window_end_utc'] as String),
      status: _parseStatus(data['status'] as String),
      createdAtUtc: DateTime.parse(data['created_at_utc'] as String),
      lastEvaluatedAtUtc: DateTime.parse(
        data['last_evaluated_at_utc'] as String,
      ),
      statusLastUpdatedAtUtc: DateTime.parse(
        data['status_last_updated_at_utc'] as String,
      ),
      finalizedAtUtc: data['finalized_at_utc'] != null
          ? DateTime.parse(data['finalized_at_utc'] as String)
          : null,
      boundVehicleId: data['bound_vehicle_id'] as String?,
      bindingTimestampUtc: data['binding_timestamp_utc'] != null
          ? DateTime.parse(data['binding_timestamp_utc'] as String)
          : null,
      bindingLatitude: (data['binding_latitude'] as num?)?.toDouble(),
      bindingLongitude: (data['binding_longitude'] as num?)?.toDouble(),
    );
  }

  ExecutionStatus _parseStatus(String name) {
    return ExecutionStatus.values.firstWhere((e) => e.name == name);
  }
}
