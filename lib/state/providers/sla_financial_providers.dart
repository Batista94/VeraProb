import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/contractual_financial_impact.dart';
import '../../application/sla_audit/projections/contractual_financial_impact_query_service.dart';
import '../../application/sla_audit/projections/contractual_financial_impact_query_service_in_memory.dart';
import '../../domain/sla_audit/contractual_financial_snapshot_repository.dart';
import '../../infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

// ── Snapshot Repository ─────────────────────────────────────

final financialSnapshotRepositoryProvider =
    Provider<ContractualFinancialSnapshotRepository>((ref) {
      return InMemoryContractualFinancialSnapshotRepository();
    });

// ── Query Service ───────────────────────────────────────────

final financialImpactQueryServiceProvider =
    Provider<ContractualFinancialImpactQueryService>((ref) {
      final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
      return ContractualFinancialImpactQueryServiceInMemory(
        snapshotRepo: snapshotRepo,
      );
    });

// ── Projection (Read Model) ────────────────────────────────

final financialImpactProvider = FutureProvider<ContractualFinancialImpact>((
  ref,
) async {
  final service = ref.watch(financialImpactQueryServiceProvider);
  return service.getImpact();
});
