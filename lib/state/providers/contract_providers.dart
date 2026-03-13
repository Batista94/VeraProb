import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/clone_contract_handler.dart';
import '../../application/sla_audit/close_contract_handler.dart';
import '../../application/sla_audit/create_contract_handler.dart';
import '../../application/sla_audit/declare_contractual_plan_handler.dart';
import '../../application/sla_audit/projections/contract_detail_view.dart';
import '../../application/sla_audit/projections/contract_query_service.dart';
import '../../application/sla_audit/projections/contract_query_service_in_memory.dart';
import '../../application/sla_audit/projections/contract_summary_view.dart';
import '../../application/sla_audit/shift_projection_service.dart';
import '../../domain/sla_audit/contract_status.dart';
import '../../domain/sla_audit/contractual_rule_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/sla_audit/in_memory_contractual_rule_repository.dart';
import '../../infrastructure/sla_audit/postgres_contract_query_service.dart';
import '../../infrastructure/sla_audit/postgres_contractual_rule_repository.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import 'auth_providers.dart';
import 'operational_zone_providers.dart';
import 'sla_providers.dart';

// ── Rule repository ──────────────────────────────────────────

final contractualRuleRepositoryProvider = Provider<ContractualRuleRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryContractualRuleRepository(),
    PersistenceMode.postgres =>
      PostgresContractualRuleRepository(ref.watch(supabaseClientProvider)),
  };
});

// ── Handlers ────────────────────────────────────────────────

final createContractHandlerProvider = Provider<CreateContractHandler>((ref) {
  return CreateContractHandler(
    contractRepository: ref.watch(contractRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
  );
});

final cloneContractHandlerProvider = Provider<CloneContractHandler>((ref) {
  return CloneContractHandler(
    contractRepository: ref.watch(contractRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
  );
});

final closeContractHandlerProvider = Provider<CloseContractHandler>((ref) {
  return CloseContractHandler(
    contractRepository: ref.watch(contractRepositoryProvider),
    ledger: ref.watch(slaAuditLedgerRepositoryProvider),
  );
});

final shiftProjectionServiceProvider = Provider<ShiftProjectionService>((ref) {
  return ShiftProjectionService(
    planRepo: ref.watch(planDeclarationRepositoryProvider),
    zoneRepo: ref.watch(operationalZoneRepositoryProvider),
    alertRepo: ref.watch(operationalAlertRepositoryProvider),
  );
});

final declareContractualPlanHandlerProvider =
    Provider<DeclareContractualPlanHandler>((ref) {
      return DeclareContractualPlanHandler(
        repository: ref.watch(planDeclarationRepositoryProvider),
        ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        ruleRepository: ref.watch(contractualRuleRepositoryProvider),
        contractRepository: ref.watch(contractRepositoryProvider),
        projectionService: ref.watch(shiftProjectionServiceProvider),
      );
    });

// ── Query Service ───────────────────────────────────────────

final contractQueryServiceProvider = Provider<ContractQueryService>((ref) {
  final mode = ref.watch(persistenceModeProvider);

  if (mode == PersistenceMode.postgres) {
    return PostgresContractQueryService(
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
final selectedContractIdProvider = StateProvider<String?>((ref) => null);

/// Active status filter on the contracts list. Null = all statuses.
final contractStatusFilterProvider = StateProvider<ContractStatus?>((ref) => null);

// ── Projections ─────────────────────────────────────────────

final contractListProvider = FutureProvider<List<ContractSummaryView>>((
  ref,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return [];

  final status = ref.watch(contractStatusFilterProvider);
  final service = ref.watch(contractQueryServiceProvider);

  return service.listContracts(
    organizationId: organizationId,
    status: status,
  );
});

final contractDetailProvider = FutureProvider.family<ContractDetailView?, String>(
  (ref, contractId) async {
    final organizationId = ref.watch(currentOrganizationIdProvider);
    if (organizationId == null) return null;

    final service = ref.watch(contractQueryServiceProvider);
    return service.getContractDetail(
      organizationId: organizationId,
      contractId: contractId,
    );
  },
);

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
      .toList()
    ..sort();
  return names;
});
