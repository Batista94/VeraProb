import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/application/sla_audit/rule_studio_command_service.dart';
import 'package:veraprob/application/sla_audit/update_contractual_rule_handler.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_rule_studio_command_service.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_rule_version_query_service.dart';
import 'contract_providers.dart';

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
        tenantValidator: ref.watch(tenantValidationServiceProvider),
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
