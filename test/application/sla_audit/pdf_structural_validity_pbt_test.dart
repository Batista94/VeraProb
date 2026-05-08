import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll, setUp, tearDown;
import 'package:veraprob/application/sla_audit/audit_package_service.dart';
import 'package:veraprob/application/sla_audit/pdf_export_service.dart';
import 'package:veraprob/application/sla_audit/reporting_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/attestation_header.dart';
import 'package:veraprob/domain/sla_audit/audit_package.dart';
import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_audit_package_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

/// **Validates: Requirements 8.2, 8.4**
///
/// Property 9: PDF structural validity
///
/// For any valid sealed AuditPackage (status = sealed, non-empty packageHash)
/// and matching BillingCycleReport (report.id == package.billingCycleReportId),
/// PdfExportService.generatePdf SHALL produce a non-empty `List<int>` whose
/// first 5 bytes decode to the ASCII string `%PDF-` (PDF magic header).

/// Generator input: controls the shape of the test fixture.
class PdfFixtureParams {
  /// Number of daily snapshots (1..10)
  final int snapshotCount;

  /// Revenue per day in cents (100..10_000_000)
  final int dailyRevenueCents;

  /// Whether to scope to a specific contract (true) or all contracts (false)
  final bool hasContractId;

  /// Tenant name length (1..50 chars from 'A')
  final int tenantNameLength;

  const PdfFixtureParams({
    required this.snapshotCount,
    required this.dailyRevenueCents,
    required this.hasContractId,
    required this.tenantNameLength,
  });

  @override
  String toString() =>
      'PdfFixtureParams(snapshots=$snapshotCount, revenue=$dailyRevenueCents, '
      'hasContract=$hasContractId, tenantLen=$tenantNameLength)';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Font bytes — loaded once for the entire suite via rootBundle ──────────
  late ByteData fontRegular;
  late ByteData fontBold;

  setUpAll(() async {
    fontRegular = await rootBundle.load('assets/fonts/Lato-Regular.ttf');
    fontBold = await rootBundle.load('assets/fonts/Lato-Bold.ttf');
  });

  // ── Constants ──────────────────────────────────────────────────────────────
  const orgId = 'org-pbt-pdf';
  const contractId = 'contract-pbt-1';
  const contractorName = 'Empresa PBT Ltda';
  const engineVersion = '7.1.0-pbt';
  const userId = 'user-pbt-1';

  // ── Glados generator for PdfFixtureParams ─────────────────────────────────
  // Uses any.combine4 to produce a tuple of (int, int, int, int) then maps
  // to PdfFixtureParams. The third int (0 or 1) encodes hasContractId.
  final fixtureParamsGen = any.combine4(
    any.intInRange(1, 11), // snapshotCount: 1..10
    any.intInRange(100, 10000001), // dailyRevenueCents: 100..10_000_000
    any.intInRange(0, 2), // 0 = hasContractId:false, 1 = true
    any.intInRange(1, 51), // tenantNameLength: 1..50
    (
      int snapshotCount,
      int dailyRevenueCents,
      int hasContractInt,
      int tenantNameLength,
    ) => PdfFixtureParams(
      snapshotCount: snapshotCount,
      dailyRevenueCents: dailyRevenueCents,
      hasContractId: hasContractInt == 1,
      tenantNameLength: tenantNameLength,
    ),
  );

  // ── Helper: build sealed fixture from params ──────────────────────────────
  Future<(AuditPackage, BillingCycleReport, PdfExportService)> buildFixture(
    PdfFixtureParams params,
    ByteData fontReg,
    ByteData fontBld,
  ) async {
    final periodStart = DateTime.utc(2026, 3, 1);
    final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);
    final cId = params.hasContractId ? contractId : null;
    final tenantName = 'T' * params.tenantNameLength;

    final snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    final auditPackageRepo = InMemoryAuditPackageRepository();
    final reportingService = ReportingService(snapshotRepo: snapshotRepo);
    final packageService = AuditPackageService(
      auditPackageRepo: auditPackageRepo,
      reportingService: reportingService,
    );

    // Seed snapshots
    for (var i = 0; i < params.snapshotCount; i++) {
      final date = DateTime.utc(2026, 3, 1 + i);
      final totalRevenue = Money(params.dailyRevenueCents);
      final snapshot = ContractualFinancialDailySnapshot.create(
        organizationId: orgId,
        contractId: cId,
        operationalDateUtc: date,
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: date.add(const Duration(hours: 1)),
        totalContractedRevenue: totalRevenue,
        protectedRevenue: Money((totalRevenue.cents * 0.80).round()),
        revenueAtRisk: Money((totalRevenue.cents * 0.15).round()),
        lostRevenue: Money((totalRevenue.cents * 0.05).round()),
        totalObligations: 10,
        executedCount: 8,
        noShowCount: 1,
        evidenceGapCount: 1,
        lastLedgerEntryId: '${100 + i}',
      );
      await snapshotRepo.save(snapshot);
    }

    // Generate report
    final report = await reportingService.generateBillingCycleReport(
      organizationId: orgId,
      periodStartUtc: periodStart,
      periodEndUtc: periodEnd,
      contractId: cId,
    );

    // Create attestation header
    final header = AttestationHeader.create(
      tenantName: tenantName,
      tenantCnpj: '12.345.678/0001-99',
      contractorName: contractorName,
      contractorCnpj: '98.765.432/0001-11',
      reportGeneratedBy: userId,
      reportGeneratedAtUtc: DateTime.utc(2026, 4, 1),
      engineVersion: engineVersion,
    );

    // Create sealed package
    final sealed = await packageService.createDraftAndSeal(
      organizationId: orgId,
      contractId: cId,
      contractorName: contractorName,
      periodStartUtc: periodStart,
      periodEndUtc: periodEnd,
      engineVersionAtGeneration: engineVersion,
      generatedByUserId: userId,
      attestationHeader: header,
    );

    final pdfService = PdfExportService(
      fontRegular: fontReg,
      fontBold: fontBld,
    );
    return (sealed, report, pdfService);
  }

  group('Feature: dependency-upgrade-phase3, '
      'Property 9: PDF structural validity', () {
    // ── PBT using Glados ────────────────────────────────────────────────────
    //
    // Core property: For any valid sealed AuditPackage and matching
    // BillingCycleReport, generatePdf produces a non-empty List<int> whose
    // first 5 bytes decode to `%PDF-`.

    Glados(fixtureParamsGen).test(
      'PBT: generatePdf produces non-empty output with %PDF- magic header '
      'for any valid sealed AuditPackage and matching BillingCycleReport',
      (params) async {
        final (sealed, report, pdfService) = await buildFixture(
          params,
          fontRegular,
          fontBold,
        );

        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );

        // Property 1: Output is non-empty
        expect(
          bytes.isNotEmpty,
          isTrue,
          reason: 'generatePdf must produce non-empty output for $params',
        );

        // Property 2: First 5 bytes decode to ASCII `%PDF-`
        expect(
          bytes.length,
          greaterThanOrEqualTo(5),
          reason: 'Output must be at least 5 bytes for PDF magic header',
        );

        final magicHeader = ascii.decode(bytes.sublist(0, 5));
        expect(
          magicHeader,
          equals('%PDF-'),
          reason:
              'First 5 bytes must decode to "%PDF-" (PDF magic header) '
              'for $params, got "$magicHeader"',
        );
      },
    );

    // ── Deterministic edge-case tests ────────────────────────────────────────

    test('single snapshot, minimal revenue: produces valid PDF', () async {
      const params = PdfFixtureParams(
        snapshotCount: 1,
        dailyRevenueCents: 100,
        hasContractId: true,
        tenantNameLength: 1,
      );
      final (sealed, report, pdfService) = await buildFixture(
        params,
        fontRegular,
        fontBold,
      );

      final bytes = await pdfService.generatePdf(
        package: sealed,
        report: report,
      );

      expect(bytes, isNotEmpty);
      expect(ascii.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });

    test(
      '10 snapshots, large revenue, no contract scope: produces valid PDF',
      () async {
        const params = PdfFixtureParams(
          snapshotCount: 10,
          dailyRevenueCents: 10000000,
          hasContractId: false,
          tenantNameLength: 50,
        );
        final (sealed, report, pdfService) = await buildFixture(
          params,
          fontRegular,
          fontBold,
        );

        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );

        expect(bytes, isNotEmpty);
        expect(ascii.decode(bytes.sublist(0, 5)), equals('%PDF-'));
      },
    );

    test(
      'without custom fonts (Helvetica fallback): produces valid PDF',
      () async {
        final periodStart = DateTime.utc(2026, 3, 1);
        final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);

        final snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
        final auditPackageRepo = InMemoryAuditPackageRepository();
        final reportingService = ReportingService(snapshotRepo: snapshotRepo);
        final packageService = AuditPackageService(
          auditPackageRepo: auditPackageRepo,
          reportingService: reportingService,
        );

        final snapshot = ContractualFinancialDailySnapshot.create(
          organizationId: orgId,
          contractId: contractId,
          operationalDateUtc: DateTime.utc(2026, 3, 1),
          operationalTimezone: 'America/Sao_Paulo',
          closedAtUtc: DateTime.utc(2026, 3, 1, 1),
          totalContractedRevenue: const Money(50000),
          protectedRevenue: const Money(40000),
          revenueAtRisk: const Money(7500),
          lostRevenue: const Money(2500),
          totalObligations: 5,
          executedCount: 4,
          noShowCount: 1,
          evidenceGapCount: 0,
          lastLedgerEntryId: '50',
        );
        await snapshotRepo.save(snapshot);

        final report = await reportingService.generateBillingCycleReport(
          organizationId: orgId,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          contractId: contractId,
        );

        final header = AttestationHeader.create(
          tenantName: 'Operadora Teste',
          tenantCnpj: '12.345.678/0001-99',
          contractorName: contractorName,
          contractorCnpj: '98.765.432/0001-11',
          reportGeneratedBy: userId,
          reportGeneratedAtUtc: DateTime.utc(2026, 4, 1),
          engineVersion: engineVersion,
        );

        final sealed = await packageService.createDraftAndSeal(
          organizationId: orgId,
          contractId: contractId,
          contractorName: contractorName,
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          engineVersionAtGeneration: engineVersion,
          generatedByUserId: userId,
          attestationHeader: header,
        );

        // No fonts — uses built-in Helvetica
        final pdfService = PdfExportService();

        final bytes = await pdfService.generatePdf(
          package: sealed,
          report: report,
        );

        expect(bytes, isNotEmpty);
        expect(ascii.decode(bytes.sublist(0, 5)), equals('%PDF-'));
      },
    );
  });
}
