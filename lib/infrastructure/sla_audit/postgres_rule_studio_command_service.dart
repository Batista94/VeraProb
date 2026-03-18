import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sla_audit/rule_studio_command_service.dart';
import '../../domain/sla_audit/contractual_rule.dart';

/// Postgres implementation of [RuleStudioCommandService].
///
/// Delegates the atomic close+insert to the `update_contractual_rule` RPC,
/// which executes both writes inside a single Postgres transaction.
class PostgresRuleStudioCommandService implements RuleStudioCommandService {
  final SupabaseClient _client;

  PostgresRuleStudioCommandService(this._client);

  @override
  Future<String> updateRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
  }) async {
    final result = await _client.rpc(
      'update_contractual_rule',
      params: {
        'p_contract_id': contractId,
        'p_old_rule_id': oldRuleId,
        'p_rule_type': ruleType.value,
        'p_new_config': newConfig,
        'p_evaluation_order': evaluationOrder,
      },
    );

    return result as String;
  }
}
