import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../domain/sla_audit/contractual_financial_snapshot_repository.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import '../sla_audit/in_memory_contractual_execution_state_repository.dart';
import '../sla_audit/in_memory_contractual_financial_snapshot_repository.dart';
import '../sla_audit/in_memory_plan_declaration_repository.dart';
import '../sla_audit/in_memory_sla_audit_ledger_repository.dart';
import '../sla_audit/postgres_plan_declaration_repository.dart';
import 'persistence_mode.dart';

/// Provider that holds the current persistence mode of the application.
/// Defaults to [PersistenceMode.inMemory].
final persistenceModeProvider = Provider<PersistenceMode>((ref) {
  return PersistenceMode.inMemory;
});

/// Centralized provider for creating repository instances based on the current [PersistenceMode].
/// This is the ONLY place where the decision of which implementation to use is made.
final persistenceProvider = Provider<PersistenceProvider>((ref) {
  final mode = ref.watch(persistenceModeProvider);
  return PersistenceProvider(mode);
});

class PersistenceProvider {
  final PersistenceMode _mode;

  PersistenceProvider(this._mode);

  PlanDeclarationRepository makePlanDeclarationRepository() {
    switch (_mode) {
      case PersistenceMode.inMemory:
        return InMemoryPlanDeclarationRepository();
      case PersistenceMode.postgres:
        return PostgresPlanDeclarationRepository();
    }
  }

  ContractualExecutionStateRepository
  makeContractualExecutionStateRepository() {
    switch (_mode) {
      case PersistenceMode.inMemory:
        return InMemoryContractualExecutionStateRepository();
      case PersistenceMode.postgres:
        throw UnimplementedError('Postgres persistence not implemented yet');
    }
  }

  SlaAuditLedgerRepository makeSlaAuditLedgerRepository() {
    switch (_mode) {
      case PersistenceMode.inMemory:
        return InMemorySlaAuditLedgerRepository();
      case PersistenceMode.postgres:
        throw UnimplementedError('Postgres persistence not implemented yet');
    }
  }

  ContractualFinancialSnapshotRepository
  makeContractualFinancialSnapshotRepository() {
    switch (_mode) {
      case PersistenceMode.inMemory:
        return InMemoryContractualFinancialSnapshotRepository();
      case PersistenceMode.postgres:
        throw UnimplementedError('Postgres persistence not implemented yet');
    }
  }
}
