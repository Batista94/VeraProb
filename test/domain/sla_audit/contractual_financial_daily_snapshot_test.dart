import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Helper para criar um snapshot de teste com engineVersion padrão.
/// Minimiza repetição nos testes existentes sem perder legibilidade.
ContractualFinancialDailySnapshot _makeSnapshot({
  String organizationId = 'org-1',
  String? contractId = 'c-1',
  DateTime? operationalDateUtc,
  String operationalTimezone = 'America/Sao_Paulo',
  DateTime? closedAtUtc,
  Money totalContractedRevenue = const Money(100000),
  Money protectedRevenue = const Money(50000),
  Money revenueAtRisk = const Money(30000),
  Money lostRevenue = const Money(20000),
  int totalObligations = 10,
  int executedCount = 8,
  int noShowCount = 1,
  int evidenceGapCount = 1,
  String? lastLedgerEntryId = '1',
  String engineVersion = 'veraprob-core_v4',
  String? previousSnapshotId,
  String? reprocessingReason,
  String? authorUserId,
}) {
  return ContractualFinancialDailySnapshot.create(
    organizationId: organizationId,
    contractId: contractId,
    operationalDateUtc: operationalDateUtc ?? DateTime.utc(2026, 3, 1, 10, 30),
    operationalTimezone: operationalTimezone,
    closedAtUtc: closedAtUtc ?? DateTime.utc(2026, 3, 2, 3, 0),
    totalContractedRevenue: totalContractedRevenue,
    protectedRevenue: protectedRevenue,
    revenueAtRisk: revenueAtRisk,
    lostRevenue: lostRevenue,
    totalObligations: totalObligations,
    executedCount: executedCount,
    noShowCount: noShowCount,
    evidenceGapCount: evidenceGapCount,
    lastLedgerEntryId: lastLedgerEntryId,
    engineVersion: engineVersion,
    previousSnapshotId: previousSnapshotId,
    reprocessingReason: reprocessingReason,
    authorUserId: authorUserId,
  );
}

void main() {
  group('ContractualFinancialDailySnapshot', () {
    // ── Existing tests (updated to include engineVersion) ──────────────────

    test('creates with correct fields and auto-calculated percentages', () {
      final snapshot = _makeSnapshot();

      expect(snapshot.contractId, 'c-1');
      expect(snapshot.operationalTimezone, 'America/Sao_Paulo');
      expect(snapshot.totalContractedRevenue, const Money(100000));
      expect(snapshot.protectedRevenue, const Money(50000));
      expect(snapshot.revenueAtRisk, const Money(30000));
      expect(snapshot.lostRevenue, const Money(20000));
    });

    test('normalizes operationalDateUtc to midnight UTC', () {
      final snapshot = _makeSnapshot(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1, 15, 45, 30),
        totalContractedRevenue: const Money(10000),
        protectedRevenue: const Money(10000),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        totalObligations: 10,
        executedCount: 10,
        noShowCount: 0,
        evidenceGapCount: 0,
      );

      expect(snapshot.operationalDateUtc, DateTime.utc(2026, 3, 1));
    });

    test('calculates percentages correctly', () {
      final snapshot = _makeSnapshot(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        totalContractedRevenue: const Money(100000), // R$ 1000.00
        protectedRevenue: const Money(50000),
        revenueAtRisk: const Money(30000),
        lostRevenue: const Money(20000),
        totalObligations: 10,
        executedCount: 5,
        noShowCount: 2,
        evidenceGapCount: 3,
      );

      expect(snapshot.riskPercentageBps, 3000);
      expect(snapshot.lossPercentageBps, 2000);
    });

    test('handles zero total revenue (no division by zero)', () {
      final snapshot = _makeSnapshot(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        totalContractedRevenue: const Money(0),
        protectedRevenue: const Money(0),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        totalObligations: 0,
        executedCount: 0,
        noShowCount: 0,
        evidenceGapCount: 0,
      );

      expect(snapshot.riskPercentageBps, 0);
      expect(snapshot.lossPercentageBps, 0);
    });

    test('is immutable (Equatable)', () {
      final s1 = _makeSnapshot(contractId: null);
      expect(s1.id, isNotEmpty);
    });

    test('riskPercentage calculation', () {
      final snapshot = _makeSnapshot(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        totalContractedRevenue: const Money(100),
        protectedRevenue: const Money(50),
        revenueAtRisk: const Money(30),
        lostRevenue: const Money(20),
        totalObligations: 10,
        executedCount: 8,
        noShowCount: 1,
        evidenceGapCount: 1,
      );
      expect(snapshot.riskPercentageBps, 3000);
    });

    // ── INV-21: Engine-version auditability (TDD — Fase 1) ────────────────

    test('[INV-21] snapshot records engineVersion supplied at creation', () {
      final snapshot = _makeSnapshot(engineVersion: 'veraprob-core_v4');

      expect(snapshot.engineVersion, 'veraprob-core_v4');
    });

    test(
      '[INV-21] create() throws DomainException for empty engineVersion',
      () {
        expect(
          () => _makeSnapshot(engineVersion: ''),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('engineVersion must not be empty'),
            ),
          ),
        );
      },
    );

    test(
      '[INV-21] create() throws DomainException for whitespace-only engineVersion',
      () {
        expect(
          () => _makeSnapshot(engineVersion: '   '),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      '[INV-21] reconstitute() accepts legacy-unversioned for historical rows',
      () {
        final snapshot = ContractualFinancialDailySnapshot.reconstitute(
          id: 'some-uuid',
          organizationId: 'org-1',
          contractId: 'c-1',
          operationalDateUtc: DateTime.utc(2026, 3, 1),
          operationalTimezone: 'America/Sao_Paulo',
          closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
          totalContractedRevenue: const Money(100000),
          protectedRevenue: const Money(50000),
          revenueAtRisk: const Money(30000),
          lostRevenue: const Money(20000),
          riskPercentageBps: 3000,
          lossPercentageBps: 2000,
          totalObligations: 10,
          executedCount: 8,
          noShowCount: 1,
          evidenceGapCount: 1,
          lastLedgerEntryId: '1',
          // Backfill value for rows created before INV-21
          engineVersion: 'legacy-unversioned',
        );

        expect(snapshot.engineVersion, 'legacy-unversioned');
      },
    );

    test(
      '[INV-21] engineVersion is included in props (Equatable identity)',
      () {
        final s1 = _makeSnapshot(engineVersion: 'veraprob-core_v4');
        final s2 = _makeSnapshot(engineVersion: 'veraprob-core_v5');

        // Different engineVersions must produce unequal snapshots
        // (UUIDs differ, but engineVersion is in props — we verify via field)
        expect(s1.engineVersion, isNot(equals(s2.engineVersion)));
        expect(s1.props.contains('veraprob-core_v4'), isTrue);
        expect(s2.props.contains('veraprob-core_v5'), isTrue);
      },
    );
  });
}
