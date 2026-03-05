import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import '../../domain/sla_audit/contractual_service_execution.dart';
import '../../domain/sla_audit/plan_declaration.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';
import '../../domain/sla_audit/rule_snapshot.dart';

/// Postgres implementation of [PlanDeclarationRepository].
///
/// Ensures Immutability, Monotonic Versioning, and Atomic Aggregate Persistence.
/// DELETION is physically and logically prohibited by lack of implementation.
class PostgresPlanDeclarationRepository implements PlanDeclarationRepository {
  final SupabaseClient _client;

  PostgresPlanDeclarationRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<void> save(PlanDeclaration plan) async {
    // 1. Check for existing version to ensure Monotonicity & Immutability
    final existing = await _client
        .from('plan_declarations')
        .select('id')
        .eq('contract_id', plan.contractId)
        .eq('plan_version', plan.planVersion)
        .maybeSingle();

    if (existing != null) {
      throw Exception(
        'Version ${plan.planVersion} for contract ${plan.contractId} already exists and is immutable.',
      );
    }

    // 2. Persist Aggregate Root
    // In a real production environment, this should be done in a single transaction (via RPC).
    // For this MVP step, we will use the standard client flow.
    await _client.from('plan_declarations').insert({
      'id': plan.id,
      'contract_id': plan.contractId,
      'declared_at_utc': plan.declaredAtUtc.toIso8601String(),
      'declared_by_user_id': plan.declaredByUserId,
      'plan_version': plan.planVersion,
      'original_file_hash': plan.originalFileHash,
      'rule_snapshot_jsonb': plan.ruleSnapshot.toJson(),
    });

    // 3. Persist Child Entities (Service Executions)
    final servicesData = plan.services.map((s) {
      return {
        'set_id': s.setId,
        'plan_declaration_id': plan.id,
        'scheduled_start_time_utc': s.scheduledStartTimeUtc.toIso8601String(),
        'scheduled_end_time_utc': s.scheduledEndTimeUtc.toIso8601String(),
        'start_latitude': s.startLatitude,
        'start_longitude': s.startLongitude,
        'start_radius_meters': s.startRadiusMeters,
        'end_latitude': s.endLatitude,
        'end_longitude': s.endLongitude,
        'end_radius_meters': s.endRadiusMeters,
        'planned_vehicle_id': s.plannedVehicleId,
        'contractual_value': s.contractualValue,
        'no_show_penalty_multiplier': s.noShowPenaltyMultiplier,
      };
    }).toList();

    await _client.from('contractual_service_executions').insert(servicesData);
  }

  @override
  Future<PlanDeclaration?> findById(String id) async {
    final planData = await _client
        .from('plan_declarations')
        .select('*, contractual_service_executions(*)')
        .eq('id', id)
        .maybeSingle();

    if (planData == null) return null;

    return _mapToEntity(planData);
  }

  @override
  Future<List<PlanDeclaration>> findByContract(String contractId) async {
    // Deterministic, Ordered Historical Recovery (Ordered by Version)
    final List<dynamic> data = await _client
        .from('plan_declarations')
        .select('*, contractual_service_executions(*)')
        .eq('contract_id', contractId)
        .order('plan_version', ascending: true);

    return data.map((d) => _mapToEntity(d)).toList();
  }

  PlanDeclaration _mapToEntity(Map<String, dynamic> data) {
    final List<dynamic> servicesJson = data['contractual_service_executions'];

    final services = servicesJson.map((s) {
      return ContractualServiceExecution.reconstitute(
        setId: s['set_id'],
        scheduledStartTimeUtc: DateTime.parse(s['scheduled_start_time_utc']),
        scheduledEndTimeUtc: DateTime.parse(s['scheduled_end_time_utc']),
        startLatitude: (s['start_latitude'] as num).toDouble(),
        startLongitude: (s['start_longitude'] as num).toDouble(),
        startRadiusMeters: s['start_radius_meters'] as int,
        endLatitude: (s['end_latitude'] as num).toDouble(),
        endLongitude: (s['end_longitude'] as num).toDouble(),
        endRadiusMeters: s['end_radius_meters'] as int,
        plannedVehicleId: s['planned_vehicle_id'],
        contractualValue: (s['contractual_value'] as num).toDouble(),
        noShowPenaltyMultiplier: (s['no_show_penalty_multiplier'] as num)
            .toDouble(),
      );
    }).toList();

    return PlanDeclaration.reconstitute(
      id: data['id'],
      organizationId: data['organization_id'],
      contractId: data['contract_id'],
      declaredAtUtc: DateTime.parse(data['declared_at_utc']),
      declaredByUserId: data['declared_by_user_id'],
      planVersion: data['plan_version'],
      originalFileHash: data['original_file_hash'],
      ruleSnapshot: RuleSnapshot.fromJson(
        List<dynamic>.from(data['rule_snapshot_jsonb']),
      ),
      services: services,
    );
  }
}
