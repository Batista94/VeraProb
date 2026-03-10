import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sla_audit/projections/sla_execution_item_view.dart';
import '../../application/sla_audit/contractual_evaluation_engine.dart';
import '../../application/sla_audit/contractual_evaluation_subscriber.dart';
import '../../application/sla_audit/contractual_financial_closing_service.dart';
import '../../application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import '../../application/sla_audit/projections/sla_execution_query_service.dart';
import '../../application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import '../../application/sla_audit/projections/sla_execution_summary.dart';
import '../../domain/entities/vehicle_operational_state.dart';
import '../../domain/sla_audit/execution_status.dart';
import '../../infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/sla_audit/sla_persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/postgres_sla_execution_query_service.dart';
import '../../domain/sla_audit/evaluation_trace_repository.dart';
import '../../infrastructure/sla_audit/postgres_evaluation_trace_repository.dart';
import '../../domain/sla_audit/operational_alert_repository.dart';
import '../../infrastructure/sla_audit/in_memory_operational_alert_repository.dart';
import '../../infrastructure/sla_audit/postgres_operational_alert_repository.dart';
import 'auth_providers.dart';
import 'fleet_providers.dart';
import 'sla_financial_providers.dart';

// Re-export Transport module repository providers so existing consumers that
// import this file continue to resolve them without modification.
export '../../infrastructure/sla_audit/sla_persistence_provider.dart'
    show
        planDeclarationRepositoryProvider,
        contractualExecutionStateRepositoryProvider,
        slaAuditLedgerRepositoryProvider,
        contractRepositoryProvider;

// ── Repositories (Singletons) ───────────────────────────────
// planDeclarationRepositoryProvider, contractualExecutionStateRepositoryProvider,
// and slaAuditLedgerRepositoryProvider are defined in sla_persistence_provider.dart
// and re-exported above. All other providers in this file use them via Riverpod.

final evaluationTraceRepositoryProvider = Provider<EvaluationTraceRepository>((
  ref,
) {
  final mode = ref.watch(persistenceModeProvider);
  if (mode == PersistenceMode.postgres) {
    return PostgresEvaluationTraceRepository(Supabase.instance.client);
  }
  return InMemoryEvaluationTraceRepository();
});

final operationalAlertRepositoryProvider = Provider<OperationalAlertRepository>(
  (ref) {
    final mode = ref.watch(persistenceModeProvider);
    if (mode == PersistenceMode.postgres) {
      return PostgresOperationalAlertRepository(Supabase.instance.client);
    }
    return InMemoryOperationalAlertRepository();
  },
);

// ── Engine ──────────────────────────────────────────────────

/// FASE 7: Registers the [ContractualEvaluationEngine] in the runtime.
/// This is the sole component authorized to produce contractual decisions.
final contractualEvaluationEngineProvider =
    Provider<ContractualEvaluationEngine>((ref) {
      return ContractualEvaluationEngine(
        executionRepo: ref.watch(contractualExecutionStateRepositoryProvider),
        planRepo: ref.watch(planDeclarationRepositoryProvider),
        ledgerRepo: ref.watch(slaAuditLedgerRepositoryProvider),
        traceRepo: ref.watch(evaluationTraceRepositoryProvider),
        alertRepo: ref.watch(operationalAlertRepositoryProvider),
      );
    });

// ── Snapshot Generator & Financial Closing ──────────────────

/// Generates daily financial snapshots from execution states.
final contractualFinancialSnapshotGeneratorProvider =
    Provider<ContractualFinancialSnapshotGenerator>((ref) {
      return ContractualFinancialSnapshotGenerator(
        executionRepo: ref.watch(contractualExecutionStateRepositoryProvider),
        snapshotRepo: ref.watch(financialSnapshotRepositoryProvider),
        ledgerRepo: ref.watch(slaAuditLedgerRepositoryProvider),
      );
    });

/// Automated daily financial closing orchestrator.
final contractualFinancialClosingServiceProvider =
    Provider<ContractualFinancialClosingService>((ref) {
      return ContractualFinancialClosingService(
        generator: ref.watch(contractualFinancialSnapshotGeneratorProvider),
      );
    });

// ── Subscriber (Reactive Orchestration) ─────────────────────

/// FASE 8: Connects the [ContractualEvaluationEngine] to live telemetry
/// and periodic sweep timers.
///
///
/// The provider layer adapts the Riverpod [StreamProvider] into a raw
/// [Stream], ensuring the subscriber never depends on Riverpod.
final contractualEvaluationSubscriberProvider =
    Provider<ContractualEvaluationSubscriber>((ref) {
      // Adapt: build raw Stream from the same sources as normalizedStateProvider,
      // bypassing the deprecated .stream accessor.
      final adapter = ref.watch(operationalDataProvider);
      final normalizer = ref.watch(operationalStateNormalizerProvider);

      final Stream<List<VehicleOperationalState>> vehicleStream = adapter
          .positionStream
          .map((positions) => normalizer.normalize(positions, knownStops: []));

      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) {
        throw StateError('Organization ID is missing for SLA Subscriber');
      }

      return ContractualEvaluationSubscriber(
        engine: ref.watch(contractualEvaluationEngineProvider),
        vehicleStream: vehicleStream,
        sweepInterval: const Duration(minutes: 1),
        organizationId: organizationId,
        closingService: ref.watch(contractualFinancialClosingServiceProvider),
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
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) {
    return SlaExecutionSummary.empty();
  }

  final service = ref.watch(slaExecutionQueryServiceProvider);
  return service.getSummary(organizationId: organizationId);
});

final slaExceptionsProvider = FutureProvider<List<SlaExecutionItemView>>((
  ref,
) async {
  final service = ref.watch(slaExecutionQueryServiceProvider);

  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return [];

  // We only want exceptions: noShow and evidenceGap
  final noShows = await service.listByStatus(
    ExecutionStatus.noShow,
    organizationId: organizationId,
  );
  final gaps = await service.listByStatus(
    ExecutionStatus.evidenceGap,
    organizationId: organizationId,
  );

  final all = [...noShows, ...gaps];

  // Sort by windowStartUtc as specified
  all.sort((a, b) => a.windowStartUtc.compareTo(b.windowStartUtc));

  return all;
});
