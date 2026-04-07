import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/sla_audit/contractual_evaluation_subscriber.dart';
import 'package:veraprob/application/sla_audit/contractual_financial_closing_service.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/application/sla_audit/sanction_simulation_service.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace_repository.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_operational_alert_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_evaluation_trace_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_operational_alert_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_execution_query_service.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'auth_providers.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'fleet_providers.dart';

// ── Re-exports from sla_persistence_provider ────────────────────────────────
// Kept here so all provider consumers import one canonical file.
export 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart'
    show
        planDeclarationRepositoryProvider,
        contractualExecutionStateRepositoryProvider,
        slaAuditLedgerRepositoryProvider,
        contractualFinancialSnapshotRepositoryProvider,
        contractRepositoryProvider,
        sanctionReviewQueueRepositoryProvider,
        justificationRepositoryProvider,
        vehicleInfractionRecurrenceRepositoryProvider;

// ── Operational Alert Repository ─────────────────────────────────────────────

final operationalAlertRepositoryProvider = Provider<OperationalAlertRepository>(
  (ref) {
    return switch (ref.watch(persistenceModeProvider)) {
      PersistenceMode.inMemory => InMemoryOperationalAlertRepository(),
      PersistenceMode.postgres => PostgresOperationalAlertRepository(
        ref.watch(supabaseClientProvider),
      ),
    };
  },
);

// ── Evaluation Trace Repository ──────────────────────────────────────────────

final evaluationTraceRepositoryProvider = Provider<EvaluationTraceRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryEvaluationTraceRepository(),
    PersistenceMode.postgres => PostgresEvaluationTraceRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

// ── SLA Execution Query Service ──────────────────────────────────────────────

final slaExecutionQueryServiceProvider = Provider<SlaExecutionQueryService>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => SlaExecutionQueryServiceInMemory(
      repo: ref.watch(contractualExecutionStateRepositoryProvider),
    ),
    PersistenceMode.postgres => SlaExecutionQueryServicePostgres(
      ref.watch(supabaseClientProvider),
    ),
  };
});

// ── Contractual Financial Closing Service ────────────────────────────────────

final contractualFinancialClosingServiceProvider =
    Provider<ContractualFinancialClosingService>((ref) {
      return ContractualFinancialClosingService(
        generator: ContractualFinancialSnapshotGenerator(
          executionRepo: ref.watch(contractualExecutionStateRepositoryProvider),
          snapshotRepo: ref.watch(
            contractualFinancialSnapshotRepositoryProvider,
          ),
          ledgerRepo: ref.watch(slaAuditLedgerRepositoryProvider),
        ),
      );
    });

// ── Sanction Simulation Service ──────────────────────────────────────────────

final sanctionSimulationServiceProvider = Provider<SanctionSimulationService>((
  ref,
) {
  return SanctionSimulationService(
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
    contracts: ref.watch(contractRepositoryProvider),
  );
});

// ── Contractual Evaluation Subscriber ───────────────────────────────────────

/// Returns null when no organizationId is available (unauthenticated state).
final contractualEvaluationSubscriberProvider =
    Provider<ContractualEvaluationSubscriber?>((ref) {
      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) return null;

      final engine = ContractualEvaluationEngine(
        executionRepo: ref.watch(contractualExecutionStateRepositoryProvider),
        planRepo: ref.watch(planDeclarationRepositoryProvider),
        ledgerRepo: ref.watch(slaAuditLedgerRepositoryProvider),
        traceRepo: ref.watch(evaluationTraceRepositoryProvider),
        alertRepo: ref.watch(operationalAlertRepositoryProvider),
      );

      final vehicleStream = ref
          .watch(normalizedStateProvider)
          .when(
            data: (states) => Stream.value(states),
            loading: () => const Stream<List<VehicleOperationalState>>.empty(),
            error: (e, s) =>
                const Stream<List<VehicleOperationalState>>.empty(),
          );

      return ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: vehicleStream,
        sweepInterval: const Duration(minutes: 5),
        organizationId: organizationId,
        closingService: ref.watch(contractualFinancialClosingServiceProvider),
      );
    });

// ── UI Read Models ───────────────────────────────────────────────────────────

/// Global SLA execution summary for the current session's organization.
final slaSummaryProvider = FutureProvider<SlaExecutionSummary>((ref) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return SlaExecutionSummary.empty();

  final service = ref.watch(slaExecutionQueryServiceProvider);
  return service.getSummary(organizationId: organizationId);
});

/// SLA exceptions (NoShow + EvidenceGap) for the current session's organization.
final slaExceptionsProvider = FutureProvider<List<SlaExecutionItemView>>((
  ref,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return [];

  final service = ref.watch(slaExecutionQueryServiceProvider);
  final noShows = await service.listByStatus(
    ExecutionStatus.noShow,
    organizationId: organizationId,
  );
  final evidenceGaps = await service.listByStatus(
    ExecutionStatus.evidenceGap,
    organizationId: organizationId,
  );

  return [...noShows, ...evidenceGaps]
    ..sort((a, b) => a.windowStartUtc.compareTo(b.windowStartUtc));
});
