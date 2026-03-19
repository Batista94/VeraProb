import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/csv_export_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/attestation_header.dart';
import 'package:veraprob/domain/sla_audit/audit_package.dart';
import 'package:veraprob/domain/sla_audit/audit_package_status.dart';
import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

void main() {
  final periodStart = DateTime.utc(2026, 3, 1);
  final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);
  const orgId = 'org-acme';
  const contractId = 'contract-bus-1';

  late CsvExportService service;

  AttestationHeader makeHeader() => AttestationHeader.create(
        tenantName: 'Operadora Alpha',
        tenantCnpj: '12.345.678/0001-99',
        contractorName: 'Empresa ACME Ltda',
        contractorCnpj: '98.765.432/0001-11',
        reportGeneratedBy: 'user-admin-1',
        reportGeneratedAtUtc: DateTime.utc(2026, 4, 1),
        engineVersion: '7.1.0-test',
      );

  ContractualFinancialDailySnapshot makeSnapshot({
    required DateTime date,
    String? lastLedgerEntryId = '100',
  }) =>
      ContractualFinancialDailySnapshot.create(
        organizationId: orgId,
        contractId: contractId,
        operationalDateUtc: date,
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: date.add(const Duration(hours: 1)),
        totalContractedRevenue: const Money(100000), // R$ 1000.00
        protectedRevenue: const Money(85000),
        revenueAtRisk: const Money(10000),
        lostRevenue: const Money(5000),
        totalObligations: 10,
        executedCount: 9,
        noShowCount: 1,
        evidenceGapCount: 0,
        lastLedgerEntryId: lastLedgerEntryId,
      );

  BillingCycleReport makeReport({List<ContractualFinancialDailySnapshot>? snapshots}) {
    final snaps = snapshots ??
        [
          makeSnapshot(date: DateTime.utc(2026, 3, 1)),
          makeSnapshot(date: DateTime.utc(2026, 3, 2)),
        ];
    return BillingCycleReport.create(
      organizationId: orgId,
      contractId: contractId,
      periodStartUtc: periodStart,
      periodEndUtc: periodEnd,
      snapshots: snaps,
      isComplete: true,
      missingDates: const [],
      generatedAtUtc: DateTime.utc(2026, 4, 1),
    );
  }

  /// Creates a sealed AuditPackage from the given report.
  AuditPackage makeSealedPackage(BillingCycleReport report) {
    final draft = AuditPackage.createDraft(
      organizationId: orgId,
      contractId: contractId,
      contractorName: 'Empresa ACME Ltda',
      periodStartUtc: periodStart,
      periodEndUtc: periodEnd,
      report: report,
      reportLedgerBoundary: '100',
      engineVersionAtGeneration: '7.1.0-test',
      generatedByUserId: 'user-admin-1',
      attestationHeader: makeHeader(),
    );
    return draft.seal();
  }

  setUp(() {
    service = CsvExportService();
  });

  group('CsvExportService.generateCsv — INV-19 Attestation Mandate', () {
    test('output starts with UTF-8 BOM (\\uFEFF) for Excel compatibility', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv.startsWith('\uFEFF'), isTrue,
          reason: 'UTF-8 BOM required for Brazilian Excel compatibility');
    });

    test('attestation comment block present — Report ID line', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('# Report ID:'));
    });

    test('attestation comment block contains Package ID', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('# Package ID:'));
      expect(csv, contains(package.id));
    });

    test('attestation contains SHA-256 package hash (INV-18)', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('SHA-256:${package.packageHash}'));
    });

    test('attestation contains tenant name and CNPJ', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('Operadora Alpha'));
      expect(csv, contains('12.345.678/0001-99'));
    });

    test('attestation contains period start and end (UTC)', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains(periodStart.toIso8601String()));
      expect(csv, contains(periodEnd.toIso8601String()));
    });

    test('attestation contains ledger boundary entry number', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('# Ledger Boundary:'));
      expect(csv, contains('Entry #${package.reportLedgerBoundary}'));
    });

    test('attestation contains immutability guarantee text', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('GARANTIA DE IMUTABILIDADE'));
    });

    test('legal notice referencing CPC Art. 369 is present', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('CPC Art. 369'));
    });
  });

  group('CsvExportService.generateCsv — Data correctness', () {
    test('column headers are present in semicolon-delimited format', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('Data Operacional'));
      expect(csv, contains('Faturamento Total (Cents)'));
      expect(csv, contains('Receita Protegida (Cents)'));
      expect(csv, contains('Receita em Risco (Cents)'));
      expect(csv, contains('Perda Financeira (Cents)'));
      expect(csv, contains('Conformidade %'));
    });

    test('snapshot rows contain correct cents values', () {
      final snaps = [makeSnapshot(date: DateTime.utc(2026, 3, 1))];
      final report = makeReport(snapshots: snaps);
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      // totalContractedRevenue = 100000 cents
      expect(csv, contains('100000'));
      // protectedRevenue = 85000 cents
      expect(csv, contains('85000'));
      // BRL formatting
      expect(csv, contains('R\$ 1000.00'));
    });

    test('TOTAL PERIODO row is present at end of data section', () {
      final report = makeReport();
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('TOTAL PERIODO'));
    });

    test('totals row aggregates multiple snapshots correctly', () {
      final snaps = [
        makeSnapshot(date: DateTime.utc(2026, 3, 1)), // 100000 cents
        makeSnapshot(date: DateTime.utc(2026, 3, 2)), // 100000 cents
      ];
      final report = makeReport(snapshots: snaps);
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      // Total = 200000 cents
      expect(csv, contains('200000'));
    });

    test('compliance percentage is correct for 9/10 executed', () {
      final snaps = [makeSnapshot(date: DateTime.utc(2026, 3, 1))];
      final report = makeReport(snapshots: snaps);
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      // 9/10 = 90.00%
      expect(csv, contains('90.00'));
    });

    test('date format is ISO date only (no time component) in data rows', () {
      final snaps = [makeSnapshot(date: DateTime.utc(2026, 3, 15))];
      final report = makeReport(snapshots: snaps);
      final package = makeSealedPackage(report);
      final csv = service.generateCsv(package: package, report: report);

      expect(csv, contains('2026-03-15'));
      // The time portion should not appear in data rows (only in attestation header)
      final dataSection = csv.split('# ===').last;
      expect(dataSection, isNot(contains('2026-03-15T')));
    });
  });

  group('CsvExportService.generateCsv — INV-18 enforcement', () {
    test('throws DomainException if package is not sealed', () {
      final report = makeReport();
      final draft = AuditPackage.createDraft(
        organizationId: orgId,
        contractId: contractId,
        contractorName: 'Empresa ACME Ltda',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        report: report,
        reportLedgerBoundary: '100',
        engineVersionAtGeneration: '7.1.0-test',
        generatedByUserId: 'user-admin-1',
        attestationHeader: makeHeader(),
      );

      expect(
        () => service.generateCsv(package: draft, report: report),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException if report ID does not match package', () {
      final report = makeReport();
      final package = makeSealedPackage(report);

      // Different report (different period → different deterministic ID)
      final otherReport = BillingCycleReport.create(
        organizationId: orgId,
        contractId: contractId,
        periodStartUtc: DateTime.utc(2026, 2, 1),
        periodEndUtc: DateTime.utc(2026, 2, 28),
        snapshots: const [],
        isComplete: false,
        missingDates: const [],
        generatedAtUtc: DateTime.utc(2026, 3, 1),
      );

      expect(
        () => service.generateCsv(package: package, report: otherReport),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException if sealed package has null hash (data integrity)', () {
      final report = makeReport();
      // Reconstitute a "sealed" package without a hash (corrupted state)
      final corrupt = AuditPackage.reconstitute(
        id: 'fake-id',
        organizationId: orgId,
        contractId: contractId,
        contractorName: 'Empresa ACME Ltda',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        billingCycleReportId: report.id,
        reportLedgerBoundary: '100',
        snapshotIds: const [],
        totalContractedRevenue: const Money(0),
        protectedRevenue: const Money(0),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        totalObligations: 0,
        executedCount: 0,
        noShowCount: 0,
        evidenceGapCount: 0,
        complianceRate: 100.0,
        packageHash: null, // Missing hash!
        hashAlgorithm: 'SHA-256',
        schemaVersion: '7.1.0',
        engineVersionAtGeneration: '7.1.0-test',
        status: AuditPackageStatus.sealed,
        previousPackageId: null,
        supersessionReason: null,
        generatedAtUtc: DateTime.utc(2026, 4, 1),
        generatedByUserId: 'user-admin-1',
        attestationHeader: makeHeader(),
      );

      expect(
        () => service.generateCsv(package: corrupt, report: report),
        throwsA(isA<DomainException>()),
      );
    });
  });
}
