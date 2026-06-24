import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/application/sla_audit/rule_studio_command_service.dart';
import 'package:veraprob/application/sla_audit/retire_contractual_rule_handler.dart';
import 'package:veraprob/application/sla_audit/schedule_contractual_rule_handler.dart';
import 'package:veraprob/application/sla_audit/update_contractual_rule_handler.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_rule_studio_command_service.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_rule_version_query_service.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'auth_providers.dart';
import 'contract_providers.dart';
import 'shared_providers.dart';
import 'package:veraprob/state/session_recovery.dart';

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
        clock: ref.watch(dateTimeProviderProvider),
      );
    });

final scheduleContractualRuleHandlerProvider =
    Provider<ScheduleContractualRuleHandler>((ref) {
      return ScheduleContractualRuleHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        commandService: ref.watch(ruleStudioCommandServiceProvider),
        rbac: RbacService(),
      );
    });

final retireContractualRuleHandlerProvider =
    Provider<RetireContractualRuleHandler>((ref) {
      return RetireContractualRuleHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        commandService: ref.watch(ruleStudioCommandServiceProvider),
        rbac: RbacService(),
      );
    });

// ── Lifecycle command wrappers (INV-13) ────────────────────────────────────────
// Convert any thrown exception into a human-readable message so features never
// import from the domain layer. `null` is the ONLY success signal.

/// Schedules a future rule version. Org/role/session are read from the canonical
/// providers here (INV-1). Returns `null` on success, else an error message.
Future<String?> scheduleContractualRule(
  WidgetRef ref, {
  required String contractId,
  String? oldRuleId,
  required SlaRuleType ruleType,
  required Map<String, dynamic> newConfig,
  required int evaluationOrder,
  required DateTime effectiveAtUtc,
}) async {
  // Resilient session recovery: attempt token refresh before giving up
  final session = await SessionRecovery.ensureSessionWidget(ref);
  if (session == null) {
    return 'Sessão expirada. Faça login novamente.';
  }
  // INV-1: Obtain organizationId from currentOrganizationIdProvider (fallback to session.orgId)
  final orgId = ref.read(currentOrganizationIdProvider) ?? session.orgId;
  try {
    await ref
        .read(scheduleContractualRuleHandlerProvider)
        .handle(
          ScheduleContractualRuleCommand(
            organizationId: orgId,
            contractId: contractId,
            oldRuleId: oldRuleId,
            ruleType: ruleType,
            newConfig: newConfig,
            evaluationOrder: evaluationOrder,
            effectiveAtUtc: effectiveAtUtc,
            callerRole: ref.read(currentUserRoleProvider),
            sessionId: session.sessionId,
          ),
        );
    return null;
  } on DomainException catch (e) {
    return e.message;
  } on IntegrityException catch (e) {
    return e.message;
  } catch (_) {
    return 'Não foi possível agendar a nova versão da regra.';
  }
}

/// Retires (closes) a rule version. Returns `null` on success, else a message.
Future<String?> retireContractualRule(
  WidgetRef ref, {
  required String ruleId,
}) async {
  // Resilient session recovery: attempt token refresh before giving up
  final session = await SessionRecovery.ensureSessionWidget(ref);
  if (session == null) {
    return 'Sessão expirada. Faça login novamente.';
  }
  // INV-1: Obtain organizationId from currentOrganizationIdProvider (fallback to session.orgId)
  final orgId = ref.read(currentOrganizationIdProvider) ?? session.orgId;
  try {
    await ref
        .read(retireContractualRuleHandlerProvider)
        .handle(
          RetireContractualRuleCommand(
            organizationId: orgId,
            ruleId: ruleId,
            callerRole: ref.read(currentUserRoleProvider),
            sessionId: session.sessionId,
          ),
        );
    return null;
  } on DomainException catch (e) {
    return e.message;
  } catch (_) {
    return 'Não foi possível aposentar a regra.';
  }
}

// ── Query Providers ───────────────────────────────────────────────────────────

/// All rule versions (history) for a contract — used by the history panel.
final ruleHistoryProvider =
    FutureProvider.family<List<RuleVersionHistoryEntry>, String>((
      ref,
      contractId,
    ) async {
      return ref
          .watch(ruleVersionQueryServiceProvider)
          .getHistory(contractId)
          .withProviderTimeout();
    });

/// Active rules per type for a contract — used by the rule cards.
final activeRulesProvider =
    FutureProvider.family<Map<SlaRuleType, RuleVersionHistoryEntry>, String>((
      ref,
      contractId,
    ) async {
      return ref
          .watch(ruleVersionQueryServiceProvider)
          .getActiveRules(contractId)
          .withProviderTimeout();
    });
