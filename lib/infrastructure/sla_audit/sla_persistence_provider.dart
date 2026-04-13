import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'in_memory_contract_repository.dart';
import 'in_memory_contractual_execution_state_repository.dart';
import 'in_memory_contractual_financial_snapshot_repository.dart';
import 'in_memory_plan_declaration_repository.dart';
import 'in_memory_sanction_review_queue_repository.dart';
import 'in_memory_sla_audit_ledger_repository.dart';
import 'justification/in_memory_justification_repository.dart';
import 'justification/postgres_justification_repository.dart';
import 'postgres_contract_repository.dart';
import 'postgres_contractual_execution_state_repository.dart';
import 'postgres_contractual_financial_snapshot_repository.dart';
import 'postgres_idempotency_store.dart';
import 'in_memory_idempotency_store.dart';
import 'postgres_plan_declaration_repository.dart';
import 'in_memory_vehicle_infraction_recurrence_repository.dart';
import 'postgres_sanction_review_queue_repository.dart';
import 'postgres_sla_audit_ledger_repository.dart';
import 'postgres_vehicle_infraction_recurrence_repository.dart';

/// Repository factory providers for the Transport (SLA Audit) module.
///
/// These providers are intentionally isolated from the Core persistence layer.
/// The Core [persistenceModeProvider] drives the implementation selection,
/// but the module owns its own repository wiring.

final planDeclarationRepositoryProvider = Provider<PlanDeclarationRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryPlanDeclarationRepository(),
    PersistenceMode.postgres => PostgresPlanDeclarationRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

final contractualExecutionStateRepositoryProvider =
    Provider<ContractualExecutionStateRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory =>
          InMemoryContractualExecutionStateRepository(),
        PersistenceMode.postgres => PostgresContractualExecutionStateRepository(
          ref.watch(supabaseClientProvider),
          ref.watch(dateTimeProviderProvider),
        ),
      };
    });

final slaAuditLedgerRepositoryProvider = Provider<SlaAuditLedgerRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemorySlaAuditLedgerRepository(),
    PersistenceMode.postgres => PostgresSlaAuditLedgerRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

final contractualFinancialSnapshotRepositoryProvider =
    Provider<ContractualFinancialSnapshotRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory =>
          InMemoryContractualFinancialSnapshotRepository(),
        PersistenceMode.postgres =>
          PostgresContractualFinancialSnapshotRepository(
            ref.watch(supabaseClientProvider),
          ),
      };
    });

final contractRepositoryProvider = Provider<ContractRepository>((ref) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryContractRepository(),
    PersistenceMode.postgres => PostgresContractRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

final sanctionReviewQueueRepositoryProvider =
    Provider<SanctionReviewQueueRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory => InMemorySanctionReviewQueueRepository(),
        PersistenceMode.postgres => PostgresSanctionReviewQueueRepository(
          ref.watch(supabaseClientProvider),
        ),
      };
    });

final justificationRepositoryProvider = Provider<JustificationRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryJustificationRepository(),
    PersistenceMode.postgres => PostgresJustificationRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

final vehicleInfractionRecurrenceRepositoryProvider =
    Provider<VehicleInfractionRecurrenceRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory =>
          const InMemoryVehicleInfractionRecurrenceRepository(),
        PersistenceMode.postgres =>
          PostgresVehicleInfractionRecurrenceRepository(
            ref.watch(supabaseClientProvider),
          ),
      };
    });

/// Idempotency store provider (INV-33).
///
/// In Postgres mode: uses [PostgresIdempotencyStore] with RPC functions.
/// In in-memory mode: uses [InMemoryIdempotencyStore] for testing only.
final idempotencyStoreProvider = Provider<IIdempotencyStore>((ref) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryIdempotencyStore(),
    PersistenceMode.postgres => PostgresIdempotencyStore(
      ref.watch(supabaseClientProvider),
    ),
  };
});
