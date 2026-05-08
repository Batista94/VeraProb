import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/state/provider_timeout.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/accept_by_contractor_handler.dart';
import 'package:veraprob/application/sla_audit/clone_contract_handler.dart';
import 'package:veraprob/application/sla_audit/close_contract_handler.dart';
import 'package:veraprob/application/sla_audit/contract_approval_command_service.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/application/sla_audit/submit_contract_for_approval_handler.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_approval_command_service.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_review_token_query_service.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:veraprob/application/sla_audit/projections/contract_detail_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/contract_query_service_in_memory.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/shift_projection_service.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_idempotency_store.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_idempotency_store.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_query_service.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_rule_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_rule_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'admin_providers.dart';
import 'auth_providers.dart';
import 'operational_zone_providers.dart';
import 'sla_providers.dart';
import 'shared_providers.dart';

// Re-export so features/ can use ContractReviewSummary without importing infra/.
export 'package:veraprob/infrastructure/sla_audit/postgres_contract_review_token_query_service.dart'
    show ContractReviewSummary;

// ── Idempotency Store ──────────────────────────────────────────

final idempotencyStoreProvider = Provider<IIdempotencyStore>((ref) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryIdempotencyStore(),
    PersistenceMode.postgres => PostgresIdempotencyStore(
      ref.watch(supabaseClientProvider),
    ),
  };
});

// ── Rule repository ──────────────────────────────────────────

final contractualRuleRepositoryProvider = Provider<ContractualRuleRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryContractualRuleRepository(),
    PersistenceMode.postgres => PostgresContractualRuleRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

// ── Tenant Validation Service ──────────────────────────────────────────

final tenantValidationServiceProvider = Provider<TenantValidationService>((
  ref,
) {
  return TenantValidationService(
    authRepository: ref.watch(authRepositoryProvider),
  );
});

// ── Handlers ────────────────────────────────────────────────

final createContractHandlerProvider = Provider<CreateContractHandler>((ref) {
  return CreateContractHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    contractRepository: ref.watch(contractRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
    clock: ref.watch(dateTimeProviderProvider),
  );
});

final cloneContractHandlerProvider = Provider<CloneContractHandler>((ref) {
  return CloneContractHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    contractRepository: ref.watch(contractRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
    clock: ref.watch(dateTimeProviderProvider),
  );
});

final closeContractHandlerProvider = Provider<CloseContractHandler>((ref) {
  return CloseContractHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    contractRepository: ref.watch(contractRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
    rbac: RbacService(),
    clock: ref.watch(dateTimeProviderProvider),
    idempotencyStore: ref.watch(idempotencyStoreProvider),
  );
});

// ── Contract Approval ────────────────────────────────────────

final contractApprovalCommandServiceProvider =
    Provider<ContractApprovalCommandService>((ref) {
      return PostgresContractApprovalCommandService(
        ref.watch(supabaseClientProvider),
      );
    });

final submitContractForApprovalHandlerProvider =
    Provider<SubmitContractForApprovalHandler>((ref) {
      return SubmitContractForApprovalHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        contractRepository: ref.watch(contractRepositoryProvider),
        approvalService: ref.watch(contractApprovalCommandServiceProvider),
        ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        rbac: RbacService(),
        clock: ref.watch(dateTimeProviderProvider),
      );
    });

final acceptByContractorHandlerProvider = Provider<AcceptByContractorHandler>((
  ref,
) {
  return AcceptByContractorHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    approvalService: ref.watch(contractApprovalCommandServiceProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
    clock: ref.watch(dateTimeProviderProvider),
  );
});

final contractReviewTokenQueryServiceProvider =
    Provider<PostgresContractReviewTokenQueryService>((ref) {
      return PostgresContractReviewTokenQueryService(
        ref.watch(supabaseClientProvider),
      );
    });

final shiftProjectionServiceProvider = Provider<ShiftProjectionService>((ref) {
  return ShiftProjectionService(
    planRepo: ref.watch(planDeclarationRepositoryProvider),
    zoneRepo: ref.watch(operationalZoneRepositoryProvider),
    alertRepo: ref.watch(operationalAlertRepositoryProvider),
    dateTimeProvider: ref.watch(dateTimeProviderProvider),
  );
});

final declareContractualPlanHandlerProvider =
    Provider<DeclareContractualPlanHandler>((ref) {
      return DeclareContractualPlanHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        repository: ref.watch(planDeclarationRepositoryProvider),
        ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        contractRepository: ref.watch(contractRepositoryProvider),
        zoneRepository: ref.watch(operationalZoneRepositoryProvider),
        vehicleRepository: ref.watch(activeVehicleRepositoryProvider),
        clock: ref.watch(dateTimeProviderProvider),
        idempotencyStore: ref.watch(idempotencyStoreProvider),
      );
    });

// ── Query Service ───────────────────────────────────────────

final contractQueryServiceProvider = Provider<ContractQueryService>((ref) {
  final mode = ref.watch(persistenceModeProvider);

  if (mode == PersistenceMode.postgres) {
    return PostgresContractQueryService(
      client: ref.watch(supabaseClientProvider),
      slaExecutionQueryService: ref.watch(slaExecutionQueryServiceProvider),
    );
  }

  return ContractQueryServiceInMemory(
    contractRepository: ref.watch(contractRepositoryProvider),
    planRepository: ref.watch(planDeclarationRepositoryProvider),
    executionStateRepository: ref.watch(
      contractualExecutionStateRepositoryProvider,
    ),
    slaExecutionQueryService: ref.watch(slaExecutionQueryServiceProvider),
  );
});

// ── UI State ────────────────────────────────────────────────

/// Null = show list. Non-null = show detail for that contractId.
class _SelectedContractIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final selectedContractIdProvider =
    NotifierProvider<_SelectedContractIdNotifier, String?>(
      _SelectedContractIdNotifier.new,
    );

/// Active status filter on the contracts list. Null = all statuses.
class _ContractStatusFilterNotifier extends Notifier<ContractStatusView?> {
  @override
  ContractStatusView? build() => null;

  void set(ContractStatusView? value) => state = value;
}

final contractStatusFilterProvider =
    NotifierProvider<_ContractStatusFilterNotifier, ContractStatusView?>(
      _ContractStatusFilterNotifier.new,
    );

// ── Projections ─────────────────────────────────────────────

final contractListProvider = FutureProvider<List<ContractSummaryView>>((
  ref,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return [];

  final status = ref.watch(contractStatusFilterProvider);
  final service = ref.watch(contractQueryServiceProvider);

  return service
      .listContracts(organizationId: organizationId, status: status)
      .withProviderTimeout();
});

// ── Contract Detail Notifier (Anti-Pipoco) ──────────────────

/// AsyncNotifier for the contract detail view (INV-33).
///
/// Supports manual state updates via [updateState] to synchronization
/// UI after command mutations without requiring a database round-trip.
class ContractDetailNotifier extends AsyncNotifier<ContractDetailView?> {
  ContractDetailNotifier(this.contractId);
  final String contractId;

  @override
  Future<ContractDetailView?> build() async {
    final organizationId = ref.watch(currentOrganizationIdProvider);
    if (organizationId == null) return null;

    final service = ref.watch(contractQueryServiceProvider);
    return service
        .getContractDetail(
          organizationId: organizationId,
          contractId: contractId,
        )
        .withProviderTimeout();
  }

  /// Manually updates the state with a new view model (INV-33).
  ///
  /// Used by command notifiers to inject partial updates (status, version)
  /// while preserving heavy aggregates (executions, financials).
  void updateState(ContractDetailView? newState) {
    state = AsyncData(newState);
  }
}

final contractDetailProvider =
    AsyncNotifierProvider.family<
      ContractDetailNotifier,
      ContractDetailView?,
      String
    >(ContractDetailNotifier.new);

/// Unique sorted contractor names across all contracts for this org.
/// Used by the zone form's contractor label Autocomplete.
final contractorNamesProvider = FutureProvider<List<String>>((ref) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return [];
  final service = ref.watch(contractQueryServiceProvider);
  final contracts = await service.listContracts(organizationId: organizationId);
  final names = contracts
      .map((c) => c.contractorName)
      .where((n) => n.trim().isNotEmpty)
      .toSet()
      .toList();
  names.sort();
  return names;
});
