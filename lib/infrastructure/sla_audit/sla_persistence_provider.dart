import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/dispute_evidence_repository.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_dispute_resolution_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_acknowledgement_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/vehicle_infraction_recurrence_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'in_memory_contract_repository.dart';
import 'in_memory_contractual_execution_state_repository.dart';
import 'in_memory_dispute_evidence_repository.dart';
import 'in_memory_dispute_reason_code_repository.dart';
import 'in_memory_contractual_financial_snapshot_repository.dart';
import 'in_memory_forensic_evidence_snapshot_repository.dart';
import 'in_memory_plan_declaration_repository.dart';
import 'in_memory_sanction_dispute_resolution_repository.dart';
import 'in_memory_sanction_acknowledgement_command_repository.dart';
import 'in_memory_sanction_review_command_repository.dart';
import 'in_memory_sanction_review_queue_repository.dart';
import 'in_memory_sla_audit_ledger_repository.dart';
import 'justification/in_memory_justification_repository.dart';
import 'justification/postgres_justification_repository.dart';
import 'postgres_contract_repository.dart';
import 'postgres_contractual_execution_state_repository.dart';
import 'postgres_dispute_evidence_repository.dart';
import 'postgres_dispute_reason_code_repository.dart';
import 'postgres_contractual_financial_snapshot_repository.dart';
import 'postgres_idempotency_store.dart';
import 'in_memory_idempotency_store.dart';
import 'postgres_plan_declaration_repository.dart';
import 'in_memory_vehicle_infraction_recurrence_repository.dart';
import 'postgres_sanction_dispute_resolution_repository.dart';
import 'postgres_sanction_acknowledgement_command_repository.dart';
import 'postgres_sanction_review_command_repository.dart';
import 'postgres_sanction_review_queue_repository.dart';
import 'postgres_forensic_evidence_snapshot_repository.dart';
import 'postgres_sla_audit_ledger_repository.dart';
import 'postgres_vehicle_infraction_recurrence_repository.dart';

/// Wired SLA Audit persistence implementations for one [PersistenceMode].
typedef SlaPersistenceBundle = ({
  PlanDeclarationRepository planDeclaration,
  ContractualExecutionStateRepository contractualExecutionState,
  SlaAuditLedgerRepository slaAuditLedger,
  ForensicEvidenceSnapshotRepository forensicEvidenceSnapshot,
  ContractualFinancialSnapshotRepository contractualFinancialSnapshot,
  ContractRepository contract,
  SanctionReviewQueueRepository sanctionReviewQueue,
  DisputeReasonCodeRepository disputeReasonCode,
  DisputeEvidenceRepository disputeEvidence,
  JustificationRepository justification,
  VehicleInfractionRecurrenceRepository vehicleInfractionRecurrence,
  IIdempotencyStore idempotencyStore,
});

/// Single switchboard for SLA Audit repos (in-memory vs Postgres).
final slaPersistenceBundleProvider = Provider<SlaPersistenceBundle>((ref) {
  final mode = ref.watch(persistenceModeProvider);

  return switch (mode) {
    PersistenceMode.inMemory => (
      planDeclaration: InMemoryPlanDeclarationRepository(),
      contractualExecutionState: InMemoryContractualExecutionStateRepository(),
      slaAuditLedger: InMemorySlaAuditLedgerRepository(),
      forensicEvidenceSnapshot: InMemoryForensicEvidenceSnapshotRepository(),
      contractualFinancialSnapshot:
          InMemoryContractualFinancialSnapshotRepository(),
      contract: InMemoryContractRepository(),
      sanctionReviewQueue: InMemorySanctionReviewQueueRepository(),
      disputeReasonCode: InMemoryDisputeReasonCodeRepository(),
      disputeEvidence: InMemoryDisputeEvidenceRepository(),
      justification: InMemoryJustificationRepository(),
      vehicleInfractionRecurrence:
          const InMemoryVehicleInfractionRecurrenceRepository(),
      idempotencyStore: InMemoryIdempotencyStore(),
    ),
    PersistenceMode.postgres => () {
      final client = ref.watch(supabaseClientProvider);
      final clock = ref.watch(dateTimeProviderProvider);
      return (
        planDeclaration: PostgresPlanDeclarationRepository(client),
        contractualExecutionState: PostgresContractualExecutionStateRepository(
          client,
          clock,
        ),
        slaAuditLedger: PostgresSlaAuditLedgerRepository(client),
        forensicEvidenceSnapshot: PostgresForensicEvidenceSnapshotRepository(
          client,
        ),
        contractualFinancialSnapshot:
            PostgresContractualFinancialSnapshotRepository(client),
        contract: PostgresContractRepository(client),
        sanctionReviewQueue: PostgresSanctionReviewQueueRepository(client),
        disputeReasonCode: PostgresDisputeReasonCodeRepository(client),
        disputeEvidence: PostgresDisputeEvidenceRepository(client),
        justification: PostgresJustificationRepository(client),
        vehicleInfractionRecurrence:
            PostgresVehicleInfractionRecurrenceRepository(client),
        idempotencyStore: PostgresIdempotencyStore(client),
      );
    }(),
  };
});

final planDeclarationRepositoryProvider = Provider<PlanDeclarationRepository>((
  ref,
) {
  return ref.watch(slaPersistenceBundleProvider).planDeclaration;
});

final contractualExecutionStateRepositoryProvider =
    Provider<ContractualExecutionStateRepository>((ref) {
      return ref.watch(slaPersistenceBundleProvider).contractualExecutionState;
    });

final slaAuditLedgerRepositoryProvider = Provider<SlaAuditLedgerRepository>((
  ref,
) {
  return ref.watch(slaPersistenceBundleProvider).slaAuditLedger;
});

final forensicEvidenceSnapshotRepositoryProvider =
    Provider<ForensicEvidenceSnapshotRepository>((ref) {
      return ref.watch(slaPersistenceBundleProvider).forensicEvidenceSnapshot;
    });

final contractualFinancialSnapshotRepositoryProvider =
    Provider<ContractualFinancialSnapshotRepository>((ref) {
      return ref
          .watch(slaPersistenceBundleProvider)
          .contractualFinancialSnapshot;
    });

final contractRepositoryProvider = Provider<ContractRepository>((ref) {
  return ref.watch(slaPersistenceBundleProvider).contract;
});

final sanctionReviewQueueRepositoryProvider =
    Provider<SanctionReviewQueueRepository>((ref) {
      return ref.watch(slaPersistenceBundleProvider).sanctionReviewQueue;
    });

/// Command repos depend on queue/ledger/vault — kept outside the bundle.
final sanctionReviewCommandRepositoryProvider =
    Provider<SanctionReviewCommandRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory => InMemorySanctionReviewCommandRepository(
          queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
          ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        ),
        PersistenceMode.postgres => PostgresSanctionReviewCommandRepository(
          ref.watch(supabaseClientProvider),
        ),
      };
    });

final sanctionAcknowledgementCommandRepositoryProvider =
    Provider<SanctionAcknowledgementCommandRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory =>
          InMemorySanctionAcknowledgementCommandRepository(
            queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
            ledger: ref.watch(slaAuditLedgerRepositoryProvider),
          ),
        PersistenceMode.postgres =>
          PostgresSanctionAcknowledgementCommandRepository(
            ref.watch(supabaseClientProvider),
          ),
      };
    });

final sanctionDisputeResolutionRepositoryProvider =
    Provider<SanctionDisputeResolutionRepository>((ref) {
      return switch (ref.watch(persistenceModeProvider)) {
        PersistenceMode.inMemory => InMemorySanctionDisputeResolutionRepository(
          queueRepo: ref.watch(sanctionReviewQueueRepositoryProvider),
          ledger: ref.watch(slaAuditLedgerRepositoryProvider),
          vault: ref.watch(forensicEvidenceSnapshotRepositoryProvider),
        ),
        PersistenceMode.postgres => PostgresSanctionDisputeResolutionRepository(
          ref.watch(supabaseClientProvider),
        ),
      };
    });

final disputeReasonCodeRepositoryProvider =
    Provider<DisputeReasonCodeRepository>((ref) {
      return ref.watch(slaPersistenceBundleProvider).disputeReasonCode;
    });

final disputeEvidenceRepositoryProvider = Provider<DisputeEvidenceRepository>((
  ref,
) {
  return ref.watch(slaPersistenceBundleProvider).disputeEvidence;
});

final justificationRepositoryProvider = Provider<JustificationRepository>((
  ref,
) {
  return ref.watch(slaPersistenceBundleProvider).justification;
});

final vehicleInfractionRecurrenceRepositoryProvider =
    Provider<VehicleInfractionRecurrenceRepository>((ref) {
      return ref
          .watch(slaPersistenceBundleProvider)
          .vehicleInfractionRecurrence;
    });

/// Idempotency store provider (INV-33).
final idempotencyStoreProvider = Provider<IIdempotencyStore>((ref) {
  return ref.watch(slaPersistenceBundleProvider).idempotencyStore;
});
