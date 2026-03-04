import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/sla_execution_item_view.dart';
import '../../application/sla_audit/contractual_evaluation_engine.dart';
import '../../application/sla_audit/projections/sla_execution_query_service.dart';
import '../../application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import '../../application/sla_audit/projections/sla_execution_summary.dart';
import '../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../domain/sla_audit/execution_status.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/postgres_sla_execution_query_service.dart';

// ── Repositories (Singletons) ───────────────────────────────

final planDeclarationRepositoryProvider = Provider<PlanDeclarationRepository>((
  ref,
) {
  return ref.watch(persistenceProvider).makePlanDeclarationRepository();
});

final contractualExecutionStateRepositoryProvider =
    Provider<ContractualExecutionStateRepository>((ref) {
      return ref
          .watch(persistenceProvider)
          .makeContractualExecutionStateRepository();
    });

final slaAuditLedgerRepositoryProvider = Provider<SlaAuditLedgerRepository>((
  ref,
) {
  return ref.watch(persistenceProvider).makeSlaAuditLedgerRepository();
});

// ── Engine ──────────────────────────────────────────────────

/// FASE 7: Registers the [ContractualEvaluationEngine] in the runtime.
/// This is the sole component authorized to produce contractual decisions.
final contractualEvaluationEngineProvider =
    Provider<ContractualEvaluationEngine>((ref) {
      return ContractualEvaluationEngine(
        executionRepo: ref.watch(contractualExecutionStateRepositoryProvider),
        ledgerRepo: ref.watch(slaAuditLedgerRepositoryProvider),
      );
    });

// ── Query Service ───────────────────────────────────────────

final slaExecutionQueryServiceProvider = Provider<SlaExecutionQueryService>((
  ref,
) {
  final mode = ref.watch(persistenceModeProvider);

  if (mode == PersistenceMode.postgres) {
    final client = ref.watch(supabaseClientProvider);
    return SlaExecutionQueryServicePostgres(client);
  }

  // Safe to watch InMemory repo since the mode is inMemory
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
