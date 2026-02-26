import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/sla_execution_item_view.dart';
import '../../application/sla_audit/projections/sla_execution_query_service.dart';
import '../../application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import '../../application/sla_audit/projections/sla_execution_summary.dart';
import '../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../domain/sla_audit/execution_status.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import '../../infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import '../../infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import '../../infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

// ── Repositories (Singletons) ───────────────────────────────

final planDeclarationRepositoryProvider = Provider<PlanDeclarationRepository>((
  ref,
) {
  return InMemoryPlanDeclarationRepository();
});

final contractualExecutionStateRepositoryProvider =
    Provider<ContractualExecutionStateRepository>((ref) {
      return InMemoryContractualExecutionStateRepository();
    });

final slaAuditLedgerRepositoryProvider = Provider<SlaAuditLedgerRepository>((
  ref,
) {
  return InMemorySlaAuditLedgerRepository();
});

// ── Query Service ───────────────────────────────────────────

final slaExecutionQueryServiceProvider = Provider<SlaExecutionQueryService>((
  ref,
) {
  final repo = ref.watch(contractualExecutionStateRepositoryProvider);
  return SlaExecutionQueryServiceInMemory(repo: repo);
});

// ── Projections (Read Models) ───────────────────────────────

final slaSummaryProvider = FutureProvider<SlaExecutionSummary>((ref) async {
  final service = ref.watch(slaExecutionQueryServiceProvider);
  return service.getSummary();
});

final slaExceptionsProvider = FutureProvider<List<SlaExecutionItemView>>((
  ref,
) async {
  final service = ref.watch(slaExecutionQueryServiceProvider);

  // We only want exceptions: noShow and evidenceGap
  final noShows = await service.listByStatus(ExecutionStatus.noShow);
  final gaps = await service.listByStatus(ExecutionStatus.evidenceGap);

  final all = [...noShows, ...gaps];

  // Sort by windowStartUtc as specified
  all.sort((a, b) => a.windowStartUtc.compareTo(b.windowStartUtc));

  return all;
});
