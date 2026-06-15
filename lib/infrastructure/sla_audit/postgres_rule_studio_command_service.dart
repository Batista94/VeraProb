// pr_scanner: ignore-regression
// Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12):
// rule lifecycle scheduling/retirement + financial amendments (INV-3/4/15/21).
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/sla_audit/rule_studio_command_service.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [RuleStudioCommandService].
///
/// Delegates each lifecycle mutation to its SECURITY DEFINER RPC, which executes
/// the atomic close+insert inside a single Postgres transaction. The RPCs gate
/// the JWT org + TENANT_ADMIN role server-side and merge not-found/unauthorized
/// into a single `RAISE EXCEPTION` (P0001) — anti-oracle at the SQL boundary.
///
/// **Error mapping (INV-10 / INV-26):** every RPC failure is translated by
/// [mapPostgrestToDomainException] — P0001 guard violations surface as
/// [IntegrityException], RLS denials (42501) as [SovereigntyViolationException].
/// A raw [PostgrestException] never crosses the infrastructure boundary.
class PostgresRuleStudioCommandService extends BasePostgresRepository
    implements RuleStudioCommandService {
  PostgresRuleStudioCommandService(super.client);

  @override
  Future<String> updateRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
    required DateTime effectiveAtUtc,
  }) async {
    try {
      final result = await client.rpc<String>(
        'update_contractual_rule',
        params: {
          'p_contract_id': contractId,
          'p_old_rule_id': oldRuleId,
          'p_rule_type': ruleType.value,
          'p_new_config': newConfig,
          'p_evaluation_order': evaluationOrder,
          // SQL param keeps legacy name p_now_utc (CREATE OR REPLACE cannot
          // rename); semantics are effective-at, guarded ±5min server-side.
          'p_now_utc': effectiveAtUtc.toIso8601String(),
        },
      );
      return result;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractual_rule',
        resourceId: contractId,
      );
    }
  }

  @override
  Future<String> scheduleRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
    required DateTime effectiveAtUtc,
  }) async {
    try {
      final result = await client.rpc<String>(
        'schedule_contractual_rule',
        params: {
          'p_contract_id': contractId,
          'p_old_rule_id': oldRuleId,
          'p_rule_type': ruleType.value,
          'p_new_config': newConfig,
          'p_evaluation_order': evaluationOrder,
          'p_effective_at_utc': effectiveAtUtc.toIso8601String(),
        },
      );
      return result;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractual_rule',
        resourceId: contractId,
      );
    }
  }

  @override
  Future<void> activateScheduledRule({required String ruleId}) async {
    try {
      await client.rpc<dynamic>(
        'activate_scheduled_rule',
        params: {'p_rule_id': ruleId},
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractual_rule',
        resourceId: ruleId,
      );
    }
  }

  @override
  Future<void> retireRule({required String ruleId}) async {
    try {
      await client.rpc<dynamic>(
        'retire_contractual_rule',
        params: {'p_rule_id': ruleId},
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractual_rule',
        resourceId: ruleId,
      );
    }
  }
}
