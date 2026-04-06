import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    PersistenceMode.postgres => PostgresPlanDeclarationRepository(),
  };
});

final contractualExecutionStateRepositoryProvider =
    Provider<ContractualExecutionStateRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory =>
          InMemoryContractualExecutionStateRepository(),
        PersistenceMode.postgres =>
          PostgresContractualExecutionStateRepository(),
      };
    });

final slaAuditLedgerRepositoryProvider = Provider<SlaAuditLedgerRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemorySlaAuditLedgerRepository(),
    PersistenceMode.postgres => PostgresSlaAuditLedgerRepository(),
  };
});

final contractualFinancialSnapshotRepositoryProvider =
    Provider<ContractualFinancialSnapshotRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory =>
          InMemoryContractualFinancialSnapshotRepository(),
        PersistenceMode.postgres =>
          PostgresContractualFinancialSnapshotRepository(),
      };
    });

final contractRepositoryProvider = Provider<ContractRepository>((ref) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryContractRepository(),
    PersistenceMode.postgres => PostgresContractRepository(),
  };
});

final sanctionReviewQueueRepositoryProvider =
    Provider<SanctionReviewQueueRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory => InMemorySanctionReviewQueueRepository(),
        PersistenceMode.postgres => PostgresSanctionReviewQueueRepository(),
      };
    });

final justificationRepositoryProvider = Provider<JustificationRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryJustificationRepository(),
    PersistenceMode.postgres => PostgresJustificationRepository(),
  };
});

final vehicleInfractionRecurrenceRepositoryProvider =
    Provider<VehicleInfractionRecurrenceRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory =>
          const InMemoryVehicleInfractionRecurrenceRepository(),
        PersistenceMode.postgres =>
          PostgresVehicleInfractionRecurrenceRepository(),
      };
    });
