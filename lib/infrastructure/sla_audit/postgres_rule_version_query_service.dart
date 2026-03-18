import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sla_audit/rule_version_history_entry.dart';
import '../../domain/sla_audit/contractual_rule.dart';

/// Query service for the Rule Studio's history panel.
///
/// All reads go through the [get_rule_version_history] RPC, which is
/// scoped to the caller's organization by JWT (INV-6: RLS).
class PostgresRuleVersionQueryService {
  final SupabaseClient _client;

  PostgresRuleVersionQueryService(this._client);

  /// Returns all rule versions for [contractId], ordered by type + version desc.
  /// Returns an empty list if no rule set exists yet for the contract.
  Future<List<RuleVersionHistoryEntry>> getHistory(String contractId) async {
    final result = await _client.rpc(
      'get_rule_version_history',
      params: {'p_contract_id': contractId},
    );

    final list = result as List? ?? [];
    return list
        .map(
          (e) => RuleVersionHistoryEntry.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  /// Returns only the currently active rules for [contractId],
  /// grouped by [SlaRuleType].
  Future<Map<SlaRuleType, RuleVersionHistoryEntry>> getActiveRules(
    String contractId,
  ) async {
    final all = await getHistory(contractId);
    return {
      for (final entry in all.where((e) => e.isActive)) entry.ruleType: entry,
    };
  }
}
