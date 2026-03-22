import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/audit_package_service.dart';
import 'package:veraprob/application/sla_audit/reporting_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/attestation_header.dart';
import 'package:veraprob/domain/sla_audit/audit_package_status.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_audit_package_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

void main() {
  late InMemoryAuditPackageRepository auditPackageRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late ReportingService reportingService;
  late AuditPackageService service;

  final periodStart = DateTime.utc(2026, 3, 1);
  final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);
  const orgId = 'org-acme';
  const contractId = 'contract-bus-1';
  const contractorName = 'Empresa ACME Ltda';
  const engineVersion = '7.1.0-test';
  const userId = 'user-admin-1';

  AttestationHeader makeHeader() => AttestationHeader.create(
    tenantName: 'Operadora Alpha',
    tenantCnpj: '12.345.678/0001-99',
    contractorName: contractorName,
    contractorCnpj: '98.765.432/0001-11',
    reportGeneratedBy: userId,
    reportGeneratedAtUtc: DateTime.utc(2026, 4, 1),
    engineVersion: engineVersion,
  );

  ContractualFinancialDailySnapshot makeSnapshot({
    required DateTime date,
    String? lastLedgerEntryId = '100',
    Money totalRevenue = const Money(100000),
  }) {
    return ContractualFinancialDailySnapshot.create(
      organizationId: orgId,
      contractId: contractId,
      operationalDateUtc: date,
      operationalTimezone: 'America/Sao_Paulo',
      closedAtUtc: date.add(const Duration(hours: 1)),
      totalContractedRevenue: totalRevenue,
      protectedRevenue: Money((totalRevenue.cents * 0.85).round()),
      revenueAtRisk: Money((totalRevenue.cents * 0.10).round()),
      lostRevenue: Money((totalRevenue.cents * 0.05).round()),
      totalObligations: 10,
      executedCount: 9,
      noShowCount: 1,
      evidenceGapCount: 0,
      lastLedgerEntryId: lastLedgerEntryId,
    );
  }

  setUp(() {
    auditPackageRepo = InMemoryAuditPackageRepository();
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    reportingService = ReportingService(snapshotRepo: snapshotRepo);
    service = AuditPackageService(
      auditPackageRepo: auditPackageRepo,
      reportingService: reportingService,
    );
  });

  group('AuditPackageService.createDraftAndSeal', () {
    test(
      'persists TWO rows: draft (row A) then sealed (row B) — D1-Canonical',
      () async {
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

        final sealed = await service.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        // D1-Canonical: TWO rows saved
        expect(auditPackageRepo.count, equals(2));

        // Row A = draft
        final draft = auditPackageRepo.all.first;
        expect(draft.status, equals(AuditPackageStatus.draft));
        expect(draft.packageHash, isNull);

        // Row B = sealed
        final sealedRow = auditPackageRepo.all.last;
        expect(sealedRow.status, equals(AuditPackageStatus.sealed));
        expect(sealedRow.packageHash, isNotNull);
        expect(sealedRow.packageHash, isNotEmpty);

        // Returned value is the sealed package
        expect(sealed.id, equals(sealedRow.id));
      },
    );

    test(
      'draft and sealed rows have DIFFERENT IDs (D1-Canonical: two-row strategy)',
      () async {
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

        await service.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        final draft = auditPackageRepo.all.first;
        final sealed = auditPackageRepo.all.last;
        expect(draft.id, isNot(equals(sealed.id)));
      },
    );

    test(
      'reportLedgerBoundary = max(snapshot.lastLedgerEntryId) across snapshots',
      () async {
        // Three snapshots with different lastLedgerEntryIds
        await snapshotRepo.save(
          makeSnapshot(date: DateTime.utc(2026, 3, 1), lastLedgerEntryId: '42'),
        );
        await snapshotRepo.save(
          makeSnapshot(date: DateTime.utc(2026, 3, 2), lastLedgerEntryId: '99'),
        );
        await snapshotRepo.save(
          makeSnapshot(date: DateTime.utc(2026, 3, 3), lastLedgerEntryId: '71'),
        );

        final sealed = await service.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        expect(sealed.reportLedgerBoundary, equals('71'));
      },
    );

    test(
      'reportLedgerBoundary = 0 when all snapshots have null lastLedgerEntryId',
      () async {
        // Create snapshot without lastLedgerEntryId (null)
        final s = ContractualFinancialDailySnapshot.create(
          organizationId: orgId,
          contractId: contractId,
          operationalDateUtc: DateTime.utc(2026, 3, 1),
          operationalTimezone: 'America/Sao_Paulo',
          closedAtUtc: DateTime.utc(2026, 3, 1, 1),
          totalContractedRevenue: const Money(100000),
          protectedRevenue: const Money(85000),
          revenueAtRisk: const Money(10000),
          lostRevenue: const Money(5000),
          totalObligations: 10,
          executedCount: 9,
          noShowCount: 1,
          evidenceGapCount: 0,
          lastLedgerEntryId: null,
        );
        await snapshotRepo.save(s);

        final sealed = await service.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        expect(sealed.reportLedgerBoundary, isNull);
      },
    );

    test('same inputs → identical packageHash (determinism)', () async {
      await snapshotRepo.save(
        makeSnapshot(date: DateTime.utc(2026, 3, 1), lastLedgerEntryId: '50'),
      );

      final sealed1 = await service.createDraftAndSeal(
        organizationId: orgId,
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      // Reset repo, create fresh service with same underlying data
      final repo2 = InMemoryAuditPackageRepository();
      final service2 = AuditPackageService(
        auditPackageRepo: repo2,
        reportingService: reportingService,
      );

      final sealed2 = await service2.createDraftAndSeal(
        organizationId: orgId,
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      expect(sealed1.packageHash, equals(sealed2.packageHash));
    });

    test(
      'idempotency guard: returns existing sealed package if already exists',
      () async {
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

        final first = await service.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        final second = await service.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        // Same package returned, no additional rows
        expect(first.id, equals(second.id));
        expect(
          auditPackageRepo.count,
          equals(2),
        ); // still draft + sealed, not 4
      },
    );

    test('sealed package passes verifyIntegrity()', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      final sealed = await service.createDraftAndSeal(
        organizationId: orgId,
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      expect(sealed.verifyIntegrity(), isTrue);
    });

    test(
      'organizationId scoping: packages from different orgs are isolated',
      () async {
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

        await service.createDraftAndSeal(
          organizationId: 'org-A',
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        final result = await auditPackageRepo.findActiveSealedPackage(
          organizationId: 'org-B',
          contractId: contractId,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
        );

        expect(result, isNull);
      },
    );
  });

  group('AuditPackageService.supersede', () {
    test(
      'saves superseded row with correct lineage and reason (INV-1)',
      () async {
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

        final original = await service.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        await service.supersede(
          currentPackageId: original.id,
          organizationId: orgId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          reason: 'Late-arriving telemetry from 2026-03-14 detected',
          engineVersionAtGeneration: '7.1.1-patch',
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        // Superseded row is persisted (INV-1: original rows are never deleted/updated)
        final supersededRow = auditPackageRepo.all.firstWhere(
          (p) => p.previousPackageId == original.id,
        );
        expect(supersededRow.status, equals(AuditPackageStatus.superseded));
        expect(supersededRow.supersessionReason, contains('Late-arriving'));
        expect(supersededRow.previousPackageId, equals(original.id));
      },
    );

    test('throws DomainException when package not found', () async {
      expect(
        () => service.supersede(
          currentPackageId: 'non-existent',
          organizationId: orgId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          reason: 'reason',
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when trying to supersede a draft', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      await service.createDraftAndSeal(
        organizationId: orgId,
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      final draftId = auditPackageRepo.all.first.id; // the draft row

      expect(
        () => service.supersede(
          currentPackageId: draftId,
          organizationId: orgId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          reason: 'reason',
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('AuditPackageService.listSealedPackages', () {
    test('returns only sealed packages for the organization', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      await service.createDraftAndSeal(
        organizationId: orgId,
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      final packages = await service.listSealedPackages(organizationId: orgId);

      expect(packages, hasLength(1));
      expect(packages.first.status, equals(AuditPackageStatus.sealed));
    });

    test('does not return packages from other organizations', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      await service.createDraftAndSeal(
        organizationId: 'org-other',
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      final packages = await service.listSealedPackages(organizationId: orgId);
      expect(packages, isEmpty);
    });
  });
}
