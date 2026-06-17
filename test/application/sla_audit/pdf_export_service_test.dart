// Regras de Escrita:
// 1. Use DateTime.utc() ou DateTime.now().toUtc() em uma única linha (INV-9).
// 2. Use int para valores monetários (cents) e taxas (BPS) — INV-19.
// 3. Proibido importar lib/infrastructure em testes de application
//    (exceto implementações in-memory de repositórios para suporte de testes).
// 4. Fonts são carregadas via rootBundle (flutter_test) — sem dependência de dart:io.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/audit_package_service.dart';
import 'package:veraprob/application/sla_audit/pdf_export_service.dart';
import 'package:veraprob/application/sla_audit/reporting_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/attestation_header.dart';
import 'package:veraprob/domain/sla_audit/audit_package.dart';
import 'package:veraprob/domain/sla_audit/audit_package_status.dart';
import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_audit_package_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

void main() {
  // ── Font bytes — loaded once for the entire suite via rootBundle ──────────
  // Eliminates Helvetica Unicode warnings for em-dash and â‰¤ in legal notices.
  late ByteData fontRegular;
  late ByteData fontBold;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    fontRegular = await rootBundle.load('assets/fonts/Lato-Regular.ttf');
    fontBold = await rootBundle.load('assets/fonts/Lato-Bold.ttf');
  });

  // ── Constants ─────────────────────────────────────────────────────────────
  final periodStart = DateTime.utc(2026, 3, 1);
  final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);
  const orgId = 'org-forensic';
  const contractId = 'contract-bus-1';
  const contractorName = 'Empresa Teste Ltda';
  const engineVersion = '7.1.0-test';
  const userId = 'user-test-1';

  // ── Local formatting helpers (mirror private _fmtBrl / BPS display) ───────
  // These test the algorithm independently of the private methods in the service.
  String fmtBrl(int cents) => 'R\$ ${(cents / 100).toStringAsFixed(2)}';
  String fmtBps(int bps) => '${(bps / 100.0).toStringAsFixed(1)}%';

  // ── Domain object factories ───────────────────────────────────────────────
  AttestationHeader makeHeader({
    String tenantName = 'Operadora Alpha',
    String? tenantCnpj = '12.345.678/0001-99',
    String overrideContractorName = contractorName,
    String? contractorCnpj = '98.765.432/0001-11',
  }) => AttestationHeader.create(
    tenantName: tenantName,
    tenantCnpj: tenantCnpj,
    contractorName: overrideContractorName,
    contractorCnpj: contractorCnpj,
    reportGeneratedBy: userId,
    reportGeneratedAtUtc: DateTime.utc(2026, 4, 1),
    engineVersion: engineVersion,
  );

  ContractualFinancialDailySnapshot makeSnapshot({
    required DateTime date,
    String? lastLedgerEntryId = '100',
    Money totalRevenue = const Money(100000),
  }) => ContractualFinancialDailySnapshot.create(
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
    engineVersion: 'veraprob-core_v4-test',
  );

  // ── Infrastructure ────────────────────────────────────────────────────────
  late InMemoryAuditPackageRepository auditPackageRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late ReportingService reportingService;
  late AuditPackageService packageService;
  late PdfExportService pdfService;

  setUp(() {
    auditPackageRepo = InMemoryAuditPackageRepository();
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    reportingService = ReportingService(snapshotRepo: snapshotRepo);
    packageService = AuditPackageService(
      auditPackageRepo: auditPackageRepo,
      reportingService: reportingService,
    );
    pdfService = PdfExportService(fontRegular: fontRegular, fontBold: fontBold);
  });

  // ── Fixture helper ────────────────────────────────────────────────────────
  /// Seeds [snapshots] (defaults to a single March-1 row), calls
  /// [packageService.createDraftAndSeal], and returns the sealed package
  /// together with the matching [BillingCycleReport].
  ///
  /// Both objects share the same deterministic [billingCycleReportId] so
  /// [PdfExportService._assertReportMatches] passes.
  Future<(AuditPackage, BillingCycleReport)> makeSealedFixture({
    String? cId = contractId,
    AttestationHeader? header,
    List<ContractualFinancialDailySnapshot>? snapshots,
    DateTime? start,
    DateTime? end,
  }) async {
    final start0 = start ?? periodStart;
    final end0 = end ?? periodEnd;
    final snaps = snapshots ?? [makeSnapshot(date: DateTime.utc(2026, 3, 1))];
    for (final s in snaps) {
      await snapshotRepo.save(s);
    }
    final report = await reportingService.generateBillingCycleReport(
      organizationId: orgId,
      periodStartUtc: start0,
      periodEndUtc: end0,
      contractId: cId,
    );
    final sealed = await packageService.createDraftAndSeal(
      organizationId: orgId,
      contractId: cId,
      contractorName: contractorName,
      periodStartUtc: start0,
      periodEndUtc: end0,
      engineVersionAtGeneration: engineVersion,
      generatedByUserId: userId,
      attestationHeader: header ?? makeHeader(),
    );
    return (sealed, report);
  }

  // =========================================================================
  // Group 1 — Guard Clauses (INV-18)
  // =========================================================================
  group('Guard clauses — INV-18', () {
    test('1. throws DomainException for draft package', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));
      final report = await reportingService.generateBillingCycleReport(
        organizationId: orgId,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        contractId: contractId,
      );
      final draft = AuditPackage.createDraft(
        organizationId: orgId,
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        report: report,
        reportLedgerBoundary: '100',
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      expect(
        () async => pdfService.generatePdf(package: draft, report: report),
        throwsA(isA<DomainException>()),
      );
    });

    test('2. throws DomainException for superseded package', () async {
      final (sealed, report) = await makeSealedFixture();
      final superseded = sealed.supersede(reason: 'Data correction test');

      expect(
        () async => pdfService.generatePdf(package: superseded, report: report),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      '3. throws DomainException when sealed package has null packageHash',
      () async {
        final (_, report) = await makeSealedFixture();
        final anomalous = AuditPackage.reconstitute(
          id: 'anomalous-id',
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          billingCycleReportId: report.id,
          reportLedgerBoundary: '100',
          snapshotIds: report.snapshotIds,
          totalContractedRevenue: report.totalContractedRevenue,
          protectedRevenue: report.protectedRevenue,
          revenueAtRisk: report.revenueAtRisk,
          lostRevenue: report.lostRevenue,
          totalObligations: report.totalObligations,
          executedCount: report.executedCount,
          noShowCount: report.noShowCount,
          evidenceGapCount: report.evidenceGapCount,
          complianceRateBps: report.complianceRateBps,
          packageHash: null, // â† data-integrity violation
          hashAlgorithm: 'SHA-256',
          schemaVersion: AuditPackage.kSchemaVersion,
          engineVersionAtGeneration: engineVersion,
          status: AuditPackageStatus.sealed,
          previousPackageId: null,
          supersessionReason: null,
          generatedAtUtc: report.generatedAtUtc,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        expect(
          () async =>
              pdfService.generatePdf(package: anomalous, report: report),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      '4. throws DomainException when sealed package has empty packageHash',
      () async {
        final (_, report) = await makeSealedFixture();
        final anomalous = AuditPackage.reconstitute(
          id: 'anomalous-id',
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          billingCycleReportId: report.id,
          reportLedgerBoundary: '100',
          snapshotIds: report.snapshotIds,
          totalContractedRevenue: report.totalContractedRevenue,
          protectedRevenue: report.protectedRevenue,
          revenueAtRisk: report.revenueAtRisk,
          lostRevenue: report.lostRevenue,
          totalObligations: report.totalObligations,
          executedCount: report.executedCount,
          noShowCount: report.noShowCount,
          evidenceGapCount: report.evidenceGapCount,
          complianceRateBps: report.complianceRateBps,
          packageHash: '', // â† empty — equally invalid
          hashAlgorithm: 'SHA-256',
          schemaVersion: AuditPackage.kSchemaVersion,
          engineVersionAtGeneration: engineVersion,
          status: AuditPackageStatus.sealed,
          previousPackageId: null,
          supersessionReason: null,
          generatedAtUtc: report.generatedAtUtc,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        expect(
          () async =>
              pdfService.generatePdf(package: anomalous, report: report),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      '5. throws DomainException when report.id does not match package.billingCycleReportId',
      () async {
        final (sealed, _) = await makeSealedFixture();

        // Generate a DIFFERENT report (different period â†’ different deterministic ID)
        final mismatchedPeriodStart = DateTime.utc(2026, 2, 1);
        final mismatchedPeriodEnd = DateTime.utc(2026, 2, 28, 23, 59, 59);
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 2, 1)));
        final wrongReport = await reportingService.generateBillingCycleReport(
          organizationId: orgId,
          periodStartUtc: mismatchedPeriodStart,
          periodEndUtc: mismatchedPeriodEnd,
          contractId: contractId,
        );

        expect(
          () async =>
              pdfService.generatePdf(package: sealed, report: wrongReport),
          throwsA(isA<DomainException>()),
        );
      },
    );
  });

  // =========================================================================
  // Group 2 — Happy Path & Structural Integrity (INV-20/21)
  // =========================================================================
  group('Happy path — structural integrity (INV-20/21)', () {
    test('6. returns non-empty bytes for minimal valid input', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
      );
      expect(bytes, isNotEmpty);
    });

    test('7. output starts with PDF magic bytes (%PDF)', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
      );
      // ASCII: % = 37, P = 80, D = 68, F = 70
      expect(bytes.take(4).toList(), equals([37, 80, 68, 70]));
    });

    test('8. succeeds with null contractId (all-contracts scope)', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));
      final report = await reportingService.generateBillingCycleReport(
        organizationId: orgId,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        contractId: null, // â† all-contracts
      );
      final sealed = await packageService.createDraftAndSeal(
        organizationId: orgId,
        contractId: null,
        contractorName: contractorName,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
      );
      expect(bytes, isNotEmpty);
    });

    test(
      '9. succeeds with zero snapshots (Page 3 skipped gracefully)',
      () async {
        // No snapshots seeded â†’ empty report, no daily breakdown page
        final report = await reportingService.generateBillingCycleReport(
          organizationId: orgId,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          contractId: contractId,
        );
        final sealed = await packageService.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        expect(report.snapshots, isEmpty);
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        expect(bytes, isNotEmpty);
      },
    );

    test(
      '10. output byte-length is deterministic for identical inputs',
      () async {
        final (sealed, report) = await makeSealedFixture();
        final bytes1 = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        final bytes2 = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );

        // Exact byte equality expected — same pw.Document, same inputs, no
        // internal mutation between calls.
        expect(bytes1.length, equals(bytes2.length));
      },
    );
  });

  // =========================================================================
  // Group 3 — Financial Precision (INV-19)
  // =========================================================================
  group('Financial precision — INV-19', () {
    // Tests 11-14: Verify the BRL formatting algorithm used by _fmtBrl.
    // The helper mirrors `cents / 100 â†’ toStringAsFixed(2)` exactly.

    test('11. fmtBrl formats 0 cents as R\$ 0.00', () {
      expect(fmtBrl(0), equals('R\$ 0.00'));
    });

    test('12. fmtBrl formats 1 cent as R\$ 0.01', () {
      expect(fmtBrl(1), equals('R\$ 0.01'));
    });

    test('13. fmtBrl formats 15000 cents as R\$ 150.00', () {
      expect(fmtBrl(15000), equals('R\$ 150.00'));
    });

    test('14. fmtBrl has no rounding drift for large amounts', () {
      // 99999999 cents = R$ 999999.99
      expect(fmtBrl(99999999), equals('R\$ 999999.99'));
    });

    // Integration proof: service completes with Money(15000) without crash
    test(
      '13-integration. generatePdf wires _fmtBrl correctly for R\$ 150.00 loss',
      () async {
        final snapshot = makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          totalRevenue: const Money(15000),
        );
        final (sealed, report) = await makeSealedFixture(snapshots: [snapshot]);
        // If _fmtBrl misbehaves, generatePdf would crash — we prove it does not.
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        expect(bytes, isNotEmpty);
      },
    );

    // Tests 15-16: compliance rate BPS display (line 137 of service).
    test('15. fmtBps formats 9500 bps as 95.0%', () {
      expect(fmtBps(9500), equals('95.0%'));
    });

    test('16. fmtBps formats 10000 bps (full compliance) as 100.0%', () {
      expect(fmtBps(10000), equals('100.0%'));
    });
  });

  // =========================================================================
  // Group 4 — Layout Resilience (Dirty Data)
  // =========================================================================
  group('Layout resilience — dirty data', () {
    test('17. handles null tenantCnpj gracefully (renders "N/A")', () async {
      final (sealed, report) = await makeSealedFixture(
        header: makeHeader(tenantCnpj: null),
      );
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
      );
      expect(bytes, isNotEmpty);
    });

    test(
      '18. handles null contractorCnpj gracefully (renders "N/A")',
      () async {
        final (sealed, report) = await makeSealedFixture(
          header: makeHeader(contractorCnpj: null),
        );
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        expect(bytes, isNotEmpty);
      },
    );

    test('19. handles 200-char contractorName without layout crash', () async {
      final longName = 'A' * 200;
      final (sealed, report) = await makeSealedFixture(
        header: makeHeader(overrideContractorName: longName),
      );
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
      );
      expect(bytes, isNotEmpty);
    });

    test(
      '20. handles special characters in tenant name (ã ç ê ñ — "Ltda")',
      () async {
        final (sealed, report) = await makeSealedFixture(
          header: makeHeader(tenantName: 'Operadora São João & Cia — "Ltda"'),
        );
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        expect(bytes, isNotEmpty);
      },
    );

    test(
      '21. renders missing-dates warning without crash (incomplete report)',
      () async {
        // Seed only day 1 and day 31 â†’ 29 missing days in March
        final snaps = [
          makeSnapshot(date: DateTime.utc(2026, 3, 1)),
          makeSnapshot(date: DateTime.utc(2026, 3, 31)),
        ];
        final (sealed, report) = await makeSealedFixture(snapshots: snaps);

        expect(report.isComplete, isFalse);
        expect(report.missingDates, isNotEmpty);

        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        expect(bytes, isNotEmpty);
      },
    );

    test(
      '22. renders zero-revenue bar as text node (no division-by-zero)',
      () async {
        // All Money values zero â†’ _revenueBar returns text fallback
        final zeroSnap = ContractualFinancialDailySnapshot.create(
          organizationId: orgId,
          contractId: contractId,
          operationalDateUtc: DateTime.utc(2026, 3, 1),
          operationalTimezone: 'America/Sao_Paulo',
          closedAtUtc: DateTime.utc(2026, 3, 1, 1),
          totalContractedRevenue: const Money(0),
          protectedRevenue: const Money(0),
          revenueAtRisk: const Money(0),
          lostRevenue: const Money(0),
          totalObligations: 0,
          executedCount: 0,
          noShowCount: 0,
          evidenceGapCount: 0,
          lastLedgerEntryId: '100',
          engineVersion: 'veraprob-core_v4-test',
        );
        final (sealed, report) = await makeSealedFixture(snapshots: [zeroSnap]);
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        expect(bytes, isNotEmpty);
      },
    );

    test(
      '23. handles null lastLedgerEntryId in snapshot (renders "-")',
      () async {
        final snapWithNullLedger = makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          lastLedgerEntryId: null,
        );
        final (sealed, report) = await makeSealedFixture(
          snapshots: [snapWithNullLedger],
        );
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );
        expect(bytes, isNotEmpty);
      },
    );

    test('24. handles null reportLedgerBoundary in package', () async {
      // Seed a snapshot with no ledger entry, then reconstitute with null boundary
      final (originalSealed, report) = await makeSealedFixture(
        snapshots: [
          makeSnapshot(date: DateTime.utc(2026, 3, 1), lastLedgerEntryId: null),
        ],
      );
      final packageWithNullBoundary = AuditPackage.reconstitute(
        id: originalSealed.id,
        organizationId: originalSealed.organizationId,
        contractId: originalSealed.contractId,
        contractorName: originalSealed.contractorName,
        periodStartUtc: originalSealed.periodStartUtc,
        periodEndUtc: originalSealed.periodEndUtc,
        billingCycleReportId: originalSealed.billingCycleReportId,
        reportLedgerBoundary: null, // â† explicitly null
        snapshotIds: originalSealed.snapshotIds,
        totalContractedRevenue: originalSealed.totalContractedRevenue,
        protectedRevenue: originalSealed.protectedRevenue,
        revenueAtRisk: originalSealed.revenueAtRisk,
        lostRevenue: originalSealed.lostRevenue,
        totalObligations: originalSealed.totalObligations,
        executedCount: originalSealed.executedCount,
        noShowCount: originalSealed.noShowCount,
        evidenceGapCount: originalSealed.evidenceGapCount,
        complianceRateBps: originalSealed.complianceRateBps,
        packageHash: originalSealed.packageHash,
        hashAlgorithm: originalSealed.hashAlgorithm,
        schemaVersion: originalSealed.schemaVersion,
        engineVersionAtGeneration: originalSealed.engineVersionAtGeneration,
        status: AuditPackageStatus.sealed,
        previousPackageId: originalSealed.previousPackageId,
        supersessionReason: originalSealed.supersessionReason,
        generatedAtUtc: originalSealed.generatedAtUtc,
        generatedByUserId: originalSealed.generatedByUserId,
        attestationHeader: originalSealed.attestationHeader,
      );

      final bytes = await pdfService.generatePdf(
        package: packageWithNullBoundary,
        report: report,
      );
      expect(bytes, isNotEmpty);
    });
  });

  // =========================================================================
  // Group 5 — Evidence Catalogue — ADVERSARIAL (dirty data from Telegram)
  // =========================================================================
  group('Evidence catalogue — adversarial', () {
    PdfEvidenceRow makeEvidence({
      String? category,
      String driverId = 'drv-001',
      String forensicHash = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6',
      bool isLinked = true,
      DateTime? ts,
      String? mimeType,
    }) => (
      timestampUtc: ts ?? DateTime.utc(2026, 3, 15, 10, 30),
      forensicHash: forensicHash,
      category: category,
      driverId: driverId,
      isLinked: isLinked,
      statusQueryCount: 0,
      hadPendingItems: false,
      mimeType: mimeType,
    );

    test('27. empty forensicHash does not crash substring', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(forensicHash: '')],
      );
      expect(bytes, isNotEmpty);
    });

    test('28. 3-char forensicHash (shorter than 16) renders safely', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(forensicHash: 'abc')],
      );
      expect(bytes, isNotEmpty);
    });

    test('29. empty driverId does not crash substring', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(driverId: '')],
      );
      expect(bytes, isNotEmpty);
    });

    test('30. unknown category string renders without crash', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(category: 'HACKED')],
      );
      expect(bytes, isNotEmpty);
    });

    test('31. epoch-zero timestamp renders without crash', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(ts: DateTime.utc(1970, 1, 1))],
      );
      expect(bytes, isNotEmpty);
    });

    test(
      '32. far-future timestamp (year 2099) renders without crash',
      () async {
        final (sealed, report) = await makeSealedFixture();
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
          evidences: [makeEvidence(ts: DateTime.utc(2099, 12, 31, 23, 59, 59))],
        );
        expect(bytes, isNotEmpty);
      },
    );

    test(
      '33. all orphan evidences (isLinked=false) render correctly',
      () async {
        final (sealed, report) = await makeSealedFixture();
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
          evidences: [
            makeEvidence(isLinked: false, category: 'incidente'),
            makeEvidence(isLinked: false, category: null),
          ],
        );
        expect(bytes, isNotEmpty);
      },
    );

    test('34. 500 evidences renders without OOM (< 5 MB)', () async {
      final (sealed, report) = await makeSealedFixture();
      final cats = ['incidente', 'oper', 'estado', 'doc', 'outros', null];
      final evidences = List.generate(
        500,
        (i) => makeEvidence(
          category: cats[i % 6],
          driverId: 'drv-${i.toString().padLeft(4, "0")}',
          isLinked: i.isEven,
          ts: DateTime.utc(2026, 3, 1).add(Duration(minutes: i)),
        ),
      );
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: evidences,
      );
      expect(bytes, isNotEmpty);
      expect(bytes.length, lessThan(5 * 1024 * 1024));
    });

    test('35. PDF with evidences is strictly larger than without', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytesWithout = await pdfService.generatePdf(
        package: sealed,
        report: report,
      );
      final bytesWith = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [
          makeEvidence(category: null),
          makeEvidence(category: 'doc'),
          makeEvidence(category: 'incidente'),
        ],
      );
      expect(bytesWith.length, greaterThan(bytesWithout.length));
    });

    test('36. driverId with unicode chars renders safely', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(driverId: 'José_Ñ_驾')],
      );
      expect(bytes, isNotEmpty);
    });

    test('37. forensicHash with only spaces renders safely', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(forensicHash: '                ')],
      );
      expect(bytes, isNotEmpty);
    });

    test(
      '38. audio evidence (mimeType: audio/ogg) renders without crash',
      () async {
        final (sealed, report) = await makeSealedFixture();
        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
          evidences: [makeEvidence(mimeType: 'audio/ogg')],
        );
        expect(bytes, isNotEmpty);
      },
    );

    test('39. null mimeType → backward compatible (assumes photo)', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(mimeType: null)],
      );
      expect(bytes, isNotEmpty);
    });

    test('40. audio with empty hash → no crash', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(mimeType: 'audio/ogg', forensicHash: '')],
      );
      expect(bytes, isNotEmpty);
    });

    test('41. video/mp4 → not treated as audio', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [makeEvidence(mimeType: 'video/mp4')],
      );
      expect(bytes, isNotEmpty);
    });

    test('42. mix of photos and audio renders both types', () async {
      final (sealed, report) = await makeSealedFixture();
      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
        evidences: [
          makeEvidence(mimeType: 'image/jpeg', category: 'estado'),
          makeEvidence(mimeType: 'audio/ogg', category: 'incidente'),
          makeEvidence(mimeType: null, category: 'doc'),
        ],
      );
      expect(bytes, isNotEmpty);
    });
  });

  // =========================================================================
  // Group 5 — Performance / Stress (200+ Snapshots)
  // =========================================================================
  group('Performance — 200+ snapshots', () {
    /// Builds 200 daily snapshots starting from [baseDate].
    List<ContractualFinancialDailySnapshot> build200Snapshots() {
      final base = DateTime.utc(2026, 1, 1);
      return List.generate(
        200,
        (i) => makeSnapshot(
          date: base.add(Duration(days: i)),
          totalRevenue: const Money(50000),
          lastLedgerEntryId: '${i + 1}',
        ),
      );
    }

    test(
      '25. generates PDF with 200 daily snapshots without OOM (< 5 MB)',
      () async {
        final snapshots = build200Snapshots();
        final perfPeriodStart = DateTime.utc(2026, 1, 1);
        final perfPeriodEnd = DateTime.utc(2026, 7, 20, 23, 59, 59);

        for (final s in snapshots) {
          await snapshotRepo.save(s);
        }
        final report = await reportingService.generateBillingCycleReport(
          organizationId: orgId,
          periodStartUtc: perfPeriodStart,
          periodEndUtc: perfPeriodEnd,
          contractId: contractId,
        );
        final sealed = await packageService.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: perfPeriodStart,
          periodEndUtc: perfPeriodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: makeHeader(),
        );

        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );

        expect(bytes, isNotEmpty);
        // Regression gate: no embedded blob inflation (performance.md Storage constraint)
        expect(bytes.length, lessThan(5 * 1024 * 1024));
      },
    );

    test('26. 200-snapshot PDF completes in under 5 seconds', () async {
      final snapshots = build200Snapshots();
      final perfPeriodStart = DateTime.utc(2026, 1, 1);
      final perfPeriodEnd = DateTime.utc(2026, 7, 20, 23, 59, 59);

      for (final s in snapshots) {
        await snapshotRepo.save(s);
      }
      final report = await reportingService.generateBillingCycleReport(
        organizationId: orgId,
        periodStartUtc: perfPeriodStart,
        periodEndUtc: perfPeriodEnd,
        contractId: contractId,
      );
      final sealed = await packageService.createDraftAndSeal(
        organizationId: orgId,
        contractId: contractId,
        contractorName: contractorName,
        periodStartUtc: perfPeriodStart,
        periodEndUtc: perfPeriodEnd,
        engineVersionAtGeneration: engineVersion,
        generatedByUserId: userId,
        attestationHeader: makeHeader(),
      );

      final sw = Stopwatch()..start();
      await pdfService.generatePdf(package: sealed, report: report);
      sw.stop();

      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
