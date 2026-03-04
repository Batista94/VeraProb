import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/contractual_financial_impact.dart';
import '../../application/sla_audit/projections/contractual_financial_impact_query_service.dart';
import '../../application/sla_audit/projections/contractual_financial_impact_query_service_in_memory.dart';
import '../../domain/sla_audit/contractual_financial_snapshot_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';

// ── Snapshot Repository ─────────────────────────────────────

final financialSnapshotRepositoryProvider =
    Provider<ContractualFinancialSnapshotRepository>((ref) {
      return ref
          .watch(persistenceProvider)
          .makeContractualFinancialSnapshotRepository();
    });

// ── Query Service ───────────────────────────────────────────

final financialImpactQueryServiceProvider =
    Provider<ContractualFinancialImpactQueryService>((ref) {
      final mode = ref.watch(persistenceModeProvider);

      if (mode == PersistenceMode.postgres) {
        throw UnimplementedError(
          'Read-model Postgres implementation not available yet',
        );
      }

      // Safe to watch InMemory repo since the mode is inMemory
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
