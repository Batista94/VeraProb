import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/shared/money.dart';
import 'auth_providers.dart';

import '../../application/sla_audit/projections/contractual_financial_impact.dart';
import '../../application/sla_audit/projections/contractual_financial_impact_query_service.dart';
import '../../application/sla_audit/projections/contractual_financial_impact_query_service_in_memory.dart';
import '../../application/sla_audit/projections/contractual_financial_trend_query_service.dart';
import '../../application/sla_audit/projections/contractual_financial_trend_query_service_in_memory.dart';
import '../../domain/sla_audit/contractual_financial_snapshot_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/sla_audit/sla_persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/postgres_contractual_financial_impact_query_service.dart';
import '../../infrastructure/sla_audit/postgres_contractual_financial_trend_query_service.dart';

// ── Snapshot Repository ─────────────────────────────────────

final financialSnapshotRepositoryProvider =
    Provider<ContractualFinancialSnapshotRepository>((ref) {
      return ref.watch(contractualFinancialSnapshotRepositoryProvider);
    });

// ── Query Service ───────────────────────────────────────────

final financialImpactQueryServiceProvider =
    Provider<ContractualFinancialImpactQueryService>((ref) {
      final mode = ref.watch(persistenceModeProvider);

      if (mode == PersistenceMode.postgres) {
        final client = ref.watch(supabaseClientProvider);
        return ContractualFinancialImpactQueryServicePostgres(client);
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
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) {
    return ContractualFinancialImpact(
      contractId: null,
      generatedAtUtc: DateTime.now().toUtc(),
      totalContractedRevenue: const Money(0),
      protectedRevenue: const Money(0),
      revenueAtRisk: const Money(0),
      lostRevenue: const Money(0),
      riskPercentageBps: 0,
      lossPercentageBps: 0,
    );
  }

  final service = ref.watch(financialImpactQueryServiceProvider);
  return service.getImpact(organizationId: organizationId);
});

final financialTrendQueryServiceProvider =
    Provider<ContractualFinancialTrendQueryService>((ref) {
      final mode = ref.watch(persistenceModeProvider);

      if (mode == PersistenceMode.postgres) {
        final client = ref.watch(supabaseClientProvider);
        return ContractualFinancialTrendQueryServicePostgres(client);
      }

      final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
      return ContractualFinancialTrendQueryServiceInMemory(
        snapshotRepo: snapshotRepo,
      );
    });
