import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [PlanDeclarationRepository].
///
/// Ensures Immutability, Monotonic Versioning, and Atomic Aggregate Persistence.
/// DELETION is physically and logically prohibited by lack of implementation.
class PostgresPlanDeclarationRepository extends BasePostgresRepository
    implements PlanDeclarationRepository {
  PostgresPlanDeclarationRepository(super.client);

  @override
  Future<PlanDeclaration> save(PlanDeclaration plan) async {
    // 1. Check for existing version to ensure Monotonicity & Immutability
    try {
      final existing = await client
          .from('plan_declarations')
          .select('id')
          .eq('organization_id', plan.organizationId)
          .eq('contract_id', plan.contractId)
          .eq('plan_version', plan.planVersion)
          .maybeSingle();

      if (existing != null) {
        throw const IntegrityException(
          'Version violation: duplicate plan version for contract.',
          field: 'plan_version',
        );
      }
    } on IntegrityException {
      rethrow;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'plan_declaration',
        resourceId: plan.contractId,
      );
    }

    // 2. Persist Aggregate Root
    await client.from('plan_declarations').insert({
      'id': plan.id,
      'contract_id': plan.contractId,
      'organization_id': plan.organizationId,
      'declared_at_utc': plan.declaredAtUtc.toIso8601String(),
      'declared_by_user_id': plan.declaredByUserId,
      'plan_version': plan.planVersion,
      'original_file_hash': plan.originalFileHash,
      'rule_snapshot_jsonb': plan.ruleSnapshot.toJson(),
      // B2B plans: persist the full ShiftPattern array for audit & JSONB integrity
      if (plan.shiftPatterns.isNotEmpty)
        'shift_patterns_payload': plan.shiftPatterns
            .map((p) => p.toJson())
            .toList(),
      if (plan.cycleAnchorDateUtc != null)
        'cycle_anchor_date_utc': plan.cycleAnchorDateUtc!.toIso8601String(),
    });

    // 3. Persist Child Entities (Service Executions)
    final servicesData = plan.services.map((s) {
      return {
        'set_id': s.setId,
        'plan_declaration_id': plan.id,
        'organization_id': plan.organizationId,
        'scheduled_start_time_utc': s.scheduledStartTimeUtc.toIso8601String(),
        'scheduled_end_time_utc': s.scheduledEndTimeUtc.toIso8601String(),
        'start_latitude': s.startLatitude,
        'start_longitude': s.startLongitude,
        'start_radius_meters': s.startRadiusMeters,
        'end_latitude': s.endLatitude,
        'end_longitude': s.endLongitude,
        'end_radius_meters': s.endRadiusMeters,
        'planned_vehicle_id': s.plannedVehicleId,
        'contractual_value_cents': s.contractualValue.cents,
        'no_show_penalty_multiplier': s.noShowPenaltyBps,
      };
    }).toList();

    await client.from('contractual_service_executions').insert(servicesData);
    return plan;
  }

  @override
  Future<PlanDeclaration?> findById(String id) async {
    final planData = await client
        .from('plan_declarations')
        .select('*, contractual_service_executions(*)')
        .eq('id', id)
        .maybeSingle();

    if (planData == null) return null;

    return _mapToEntity(planData);
  }

  @override
  Future<List<PlanDeclaration>> findByContract(
    String contractId, {
    required String organizationId,
  }) async {
    // Deterministic, Ordered Historical Recovery (Ordered by Version)
    final List<dynamic> data = await client
        .from('plan_declarations')
        .select('*, contractual_service_executions(*)')
        .eq('organization_id', organizationId)
        .eq('contract_id', contractId)
        .order('plan_version', ascending: true);

    return data.map((d) => _mapToEntity(d)).toList();
  }

  @override
  Future<List<PlanDeclaration>> findByOrganization(
    String organizationId,
  ) async {
    final List<dynamic> data = await client
        .from('plan_declarations')
        .select('*, contractual_service_executions(*)')
        .eq('organization_id', organizationId)
        .order('plan_version', ascending: true);

    return data.map((d) => _mapToEntity(d)).toList();
  }

  @override
  Future<void> saveProjectedSets(
    String planDeclarationId,
    List<ContractualServiceExecution> sets, {
    required String organizationId,
  }) async {
    if (sets.isEmpty) return;

    final data = sets.map((s) {
      return {
        'set_id': s.setId,
        'plan_declaration_id': planDeclarationId,
        'organization_id': organizationId,
        'scheduled_start_time_utc': s.scheduledStartTimeUtc.toIso8601String(),
        'scheduled_end_time_utc': s.scheduledEndTimeUtc.toIso8601String(),
        'start_latitude': s.startLatitude,
        'start_longitude': s.startLongitude,
        'start_radius_meters': s.startRadiusMeters,
        'end_latitude': s.endLatitude,
        'end_longitude': s.endLongitude,
        'end_radius_meters': s.endRadiusMeters,
        'planned_vehicle_id': s.plannedVehicleId,
        'contractual_value_cents': s.contractualValue.cents,
        'no_show_penalty_multiplier': s.noShowPenaltyBps,
        'origin_zone_id': s.originZoneId,
        'destination_zone_id': s.destinationZoneId,
        'operational_date': s.operationalDate != null
            ? '${s.operationalDate!.year}-'
                  '${s.operationalDate!.month.toString().padLeft(2, '0')}-'
                  '${s.operationalDate!.day.toString().padLeft(2, '0')}'
            : null,
        'shift_pattern_index': s.shiftPatternIndex,
        'delay_tolerance_minutes': s.delayToleranceMinutes,
        'delay_penalty_per_minute_cents': s.delayPenaltyPerMinute?.cents,
        'downgrade_penalty_flat_cents': s.downgradePenaltyFlat?.cents,
      };
    }).toList();

    // Upsert with ignoreDuplicates — idempotency via unique constraint
    // (plan_declaration_id, shift_pattern_index, operational_date)
    await client
        .from('contractual_service_executions')
        .upsert(data, onConflict: 'set_id', ignoreDuplicates: true);
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
        contractualValue: Money((s['contractual_value_cents'] as num).toInt()),
        noShowPenaltyBps: (s['no_show_penalty_multiplier'] as num).toInt(),
        originZoneId: s['origin_zone_id'],
        destinationZoneId: s['destination_zone_id'],
        operationalDate: s['operational_date'] != null
            ? DateTime.parse('${s['operational_date']}T00:00:00.000Z')
            : null,
        shiftPatternIndex: s['shift_pattern_index'],
        delayToleranceMinutes: s['delay_tolerance_minutes'],
        delayPenaltyPerMinute: s['delay_penalty_per_minute_cents'] != null
            ? Money((s['delay_penalty_per_minute_cents'] as num).toInt())
            : null,
        downgradePenaltyFlat: s['downgrade_penalty_flat_cents'] != null
            ? Money((s['downgrade_penalty_flat_cents'] as num).toInt())
            : null,
      );
    }).toList();

    final shiftPatternsJson = data['shift_patterns_payload'];
    final shiftPatterns = shiftPatternsJson != null
        ? (shiftPatternsJson as List<dynamic>)
              .map(
                (p) =>
                    ShiftPattern.fromJson(Map<String, dynamic>.from(p as Map)),
              )
              .toList()
        : <ShiftPattern>[];

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
      shiftPatterns: shiftPatterns,
      cycleAnchorDateUtc: data['cycle_anchor_date_utc'] != null
          ? DateTime.parse(data['cycle_anchor_date_utc'] as String).toUtc()
          : null,
      previousHash: data['previous_hash'] as String?,
      currentHash: data['current_hash'] as String?,
    );
  }
}
