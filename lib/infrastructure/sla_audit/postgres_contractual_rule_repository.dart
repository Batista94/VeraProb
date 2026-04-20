import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule_repository.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

class PostgresContractualRuleRepository
    with PostgresErrorInterceptor
    implements ContractualRuleRepository {
  final SupabaseClient _client;

  PostgresContractualRuleRepository(this._client);

  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String orgId,
    String contractId,
  ) async {
    try {
      final ruleSetMap = await _client
          .from('contract_rule_sets')
          .select('id')
          .eq('organization_id', orgId)
          .eq('contract_id', contractId)
          .maybeSingle();

      if (ruleSetMap == null) {
        return const RuleSnapshot([]);
      }

      final ruleSetId = ruleSetMap['id'];
      final activeRulesRaw = await _client
          .from('contract_rule_versions')
          .select()
          .eq('rule_set_id', ruleSetId)
          .isFilter('active_to_utc', null);

      final activeRules = activeRulesRaw as List;

      final List<RuleSnapshotItem> items = activeRules.map((row) {
        return RuleSnapshotItem(
          ruleId: row['id'] as String,
          ruleType: SlaRuleType.values.firstWhere(
            (e) => e.value == row['rule_type'],
            orElse: () => SlaRuleType.maxToleranceDelay,
          ),
          config: row['rule_config'] as Map<String, dynamic>,
          ruleVersion: row['rule_version'] as int,
          evaluationOrder: row['evaluation_order'] as int,
        );
      }).toList();

      return RuleSnapshot(items);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'contractual_rule');
    }
  }

  @override
  Future<void> saveRule(ContractualRule rule) async {
    try {
      throw UnimplementedError(
        'Admin application handler manages saveRule using discrete transactions.',
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'contractual_rule');
    }
  }
}
