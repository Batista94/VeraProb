import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_financial_snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'FASE 5 - Financial Snapshot Repository Postgres Tests (contractual_financial_snapshot)',
    () {
      late SupabaseClient client;
      late PostgresContractualFinancialSnapshotRepository repository;
      const uuid = Uuid();

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repository = PostgresContractualFinancialSnapshotRepository(client);
        }
      });

      test('1. Create and reconstitute a new snapshot works correctly', () async {
        final contractId = uuid.v4();
        // last_ledger_entry_id is BIGINT FK → sla_audit_ledger.id (auto-generated).
        // We cannot pre-insert a ledger row in this test, so pass null.
        final operationalDate = DateTime.utc(2026, 3, 1);
        final closedAt = DateTime.now().toUtc();

        final snapshot = ContractualFinancialDailySnapshot.create(
          organizationId: PostgresTestConfig.testOrgId,
          contractId: contractId,
          operationalDateUtc: operationalDate,
          operationalTimezone: 'America/Sao_Paulo',
          closedAtUtc: closedAt,
          totalContractedRevenue: const Money(1000000), // R$ 10.000,00
          protectedRevenue: const Money(800000), // R$ 8.000,00
          revenueAtRisk: const Money(150000), // R$ 1.500,00
          lostRevenue: const Money(50000), // R$ 500,00
          totalObligations: 100,
          executedCount: 80,
          noShowCount: 5,
          evidenceGapCount: 15,
          lastLedgerEntryId: null,
        );

        await repository.save(snapshot);

        final contractSnapshots = await repository.findAll(
          organizationId: PostgresTestConfig.testOrgId,
          contractId: contractId,
        );
        expect(contractSnapshots.length, 1);

        final loaded = contractSnapshots.first;
        expect(loaded.id, snapshot.id);
        expect(loaded.totalContractedRevenue.cents, 1000000);
        expect(loaded.riskPercentageBps, 1500); // 1.5k over 10k
        expect(loaded.lossPercentageBps, 500); // 500 over 10k
        expect(loaded.lastLedgerEntryId, isNull);
        expect(loaded.previousSnapshotId, isNull);
      });

      test(
        '2. Snapshot chain linking properly resolves superseded logic without destroying old data',
        () async {
          final contractId = uuid.v4();
          final operationalDate = DateTime.utc(2026, 3, 2);

          // Original Generation
          final originalSnapshot = ContractualFinancialDailySnapshot.create(
            organizationId: PostgresTestConfig.testOrgId,
            contractId: contractId,
            operationalDateUtc: operationalDate,
            operationalTimezone: 'America/Sao_Paulo',
            closedAtUtc: DateTime.now().toUtc().subtract(
              const Duration(hours: 1),
            ),
            totalContractedRevenue: const Money(1000000),
            protectedRevenue: const Money(500000),
            revenueAtRisk: const Money(500000),
            lostRevenue: const Money(0),
            totalObligations: 100,
            executedCount: 50,
            noShowCount: 0,
            evidenceGapCount: 50,
            lastLedgerEntryId: uuid.v4(),
          );

          await repository.save(originalSnapshot);

          // Reprocessing Generation (creates new one referencing the old one)
          final reprocessedSnapshot = ContractualFinancialDailySnapshot.create(
            organizationId: PostgresTestConfig.testOrgId,
            contractId: contractId,
            operationalDateUtc: operationalDate,
            operationalTimezone: 'America/Sao_Paulo',
            closedAtUtc: DateTime.now().toUtc(),
            totalContractedRevenue: const Money(1000000),
            protectedRevenue: const Money(800000),
            revenueAtRisk: const Money(200000),
            lostRevenue: const Money(0),
            totalObligations: 100,
            executedCount: 80,
            noShowCount: 0,
            evidenceGapCount: 20,
            lastLedgerEntryId: uuid.v4(),
            previousSnapshotId: originalSnapshot.id,
            reprocessingReason: 'Late operator check-in',
          );

          await repository.save(reprocessedSnapshot);

          // Native findAll rules state it should ONLY return the "active" snapshots (head of chain)
          // but the original one MUST persist in the database
          final activeContractSnapshots = await repository.findAll(
            organizationId: PostgresTestConfig.testOrgId,
            contractId: contractId,
          );

          expect(
            activeContractSnapshots.length,
            1,
            reason: 'Repository findAll should hide superseded snapshots',
          );

          expect(activeContractSnapshots.first.id, reprocessedSnapshot.id);

          // Proving Immutability/Integrity that original still exists unmodified
          final rawOriginalQuery = await client
              .from('contractual_financial_snapshot')
              .select()
              .eq('id', originalSnapshot.id)
              .single();

          expect(rawOriginalQuery['id'], originalSnapshot.id);
          expect(
            rawOriginalQuery['protected_revenue_cents'],
            500000,
          ); // Remained 5k
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
