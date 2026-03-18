import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/rule_version_history_entry.dart';
import '../../application/sla_audit/rule_studio_command_service.dart';
import '../../application/sla_audit/update_contractual_rule_handler.dart';
import '../../domain/sla_audit/contractual_rule.dart';
import '../../domain/services/rbac_service.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/postgres_rule_studio_command_service.dart';
import '../../infrastructure/sla_audit/postgres_rule_version_query_service.dart';

// ── Infrastructure ────────────────────────────────────────────────────────────

final ruleStudioCommandServiceProvider = Provider<RuleStudioCommandService>((
  ref,
) {
  return PostgresRuleStudioCommandService(ref.watch(supabaseClientProvider));
});

final ruleVersionQueryServiceProvider =
    Provider<PostgresRuleVersionQueryService>((ref) {
      return PostgresRuleVersionQueryService(ref.watch(supabaseClientProvider));
    });

// ── Handlers ─────────────────────────────────────────────────────────────────

final updateContractualRuleHandlerProvider =
    Provider<UpdateContractualRuleHandler>((ref) {
      return UpdateContractualRuleHandler(
        commandService: ref.watch(ruleStudioCommandServiceProvider),
        rbac: RbacService(),
      );
    });

// ── Query Providers ───────────────────────────────────────────────────────────

/// All rule versions (history) for a contract — used by the history panel.
final ruleHistoryProvider =
    FutureProvider.family<List<RuleVersionHistoryEntry>, String>((
      ref,
      contractId,
    ) async {
      return ref.watch(ruleVersionQueryServiceProvider).getHistory(contractId);
    });

/// Active rules per type for a contract — used by the rule cards.
final activeRulesProvider =
    FutureProvider.family<Map<SlaRuleType, RuleVersionHistoryEntry>, String>((
      ref,
      contractId,
    ) async {
      return ref
          .watch(ruleVersionQueryServiceProvider)
          .getActiveRules(contractId);
    });
