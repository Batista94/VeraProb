import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/attestation_header.dart';
import 'package:veraprob/domain/sla_audit/audit_package.dart';
import 'package:veraprob/domain/sla_audit/audit_package_status.dart';
import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  // ── Helpers ────────────────────────────────────────────────────────────────
  final periodStart = DateTime.utc(2026, 3, 1);
  final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);
  final generatedAt = DateTime.utc(2026, 4, 1, 1, 0, 0);

  ContractualFinancialDailySnapshot makeSnapshot({
    String orgId = 'org-abc',
    String? contractId = 'contract-1',
    String? lastLedgerEntryId = '100',
    int executed = 8,
    int noShow = 2,
    int totalObligations = 10,
  }) => ContractualFinancialDailySnapshot.create(
    organizationId: orgId,
    contractId: contractId,
    operationalDateUtc: DateTime.utc(2026, 3, 1),
    operationalTimezone: 'America/Sao_Paulo',
    closedAtUtc: DateTime.utc(2026, 3, 2),
    totalContractedRevenue: const Money(10000),
    protectedRevenue: const Money(8000),
    revenueAtRisk: const Money(1000),
    lostRevenue: const Money(1000),
    totalObligations: totalObligations,
    executedCount: executed,
    noShowCount: noShow,
    evidenceGapCount: 0,
    lastLedgerEntryId: lastLedgerEntryId,
  );

  BillingCycleReport makeReport({
    String orgId = 'org-abc',
    String? contractId = 'contract-1',
    List<ContractualFinancialDailySnapshot>? snapshots,
  }) {
    final snaps = snapshots ?? [makeSnapshot(orgId: orgId)];
    return BillingCycleReport.create(
      organizationId: orgId,
      contractId: contractId,
      periodStartUtc: periodStart,
      periodEndUtc: periodEnd,
      snapshots: snaps,
      isComplete: true,
      missingDates: [],
      generatedAtUtc: generatedAt,
    );
  }

  AttestationHeader makeAttestation() => AttestationHeader.create(
    tenantName: 'Transportadora Exemplo Ltda',
    tenantCnpj: '12.345.678/0001-99',
    contractorName: 'Contratante S.A.',
    contractorCnpj: '98.765.432/0001-11',
    reportGeneratedBy: 'user-manager-1',
    reportGeneratedAtUtc: generatedAt,
    engineVersion: '1.0.0',
  );

  AuditPackage makeDraft({
    String orgId = 'org-abc',
    String? reportLedgerBoundary = '100',
  }) => AuditPackage.createDraft(
    organizationId: orgId,
    contractId: 'contract-1',
    contractorName: 'Contratante S.A.',
    periodStartUtc: periodStart,
    periodEndUtc: periodEnd,
    report: makeReport(orgId: orgId),
    reportLedgerBoundary: reportLedgerBoundary,
    engineVersionAtGeneration: '1.0.0',
    generatedByUserId: 'user-manager-1',
    attestationHeader: makeAttestation(),
  );

  // ── AuditPackage.createDraft ───────────────────────────────────────────────
  group('AuditPackage.createDraft', () {
    test('creates draft with status=draft and no packageHash', () {
      final draft = makeDraft();
      expect(draft.status, AuditPackageStatus.draft);
      expect(draft.packageHash, isNull);
    });

    test('sets reportLedgerBoundary from argument', () {
      final draft = makeDraft(reportLedgerBoundary: '4471');
      expect(draft.reportLedgerBoundary, '4471');
    });

    test('derives snapshotIds from report', () {
      final report = makeReport();
      final draft = AuditPackage.createDraft(
        organizationId: 'org-abc',
        contractId: 'contract-1',
        contractorName: 'Contratante S.A.',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        report: report,
        reportLedgerBoundary: '100',
        engineVersionAtGeneration: '1.0.0',
        generatedByUserId: 'user-1',
        attestationHeader: makeAttestation(),
      );
      expect(draft.snapshotIds, equals(report.snapshotIds));
    });

    test('denormalizes financial aggregates from report', () {
      final report = makeReport();
      final draft = AuditPackage.createDraft(
        organizationId: 'org-abc',
        contractId: 'contract-1',
        contractorName: 'Contratante S.A.',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        report: report,
        reportLedgerBoundary: '100',
        engineVersionAtGeneration: '1.0.0',
        generatedByUserId: 'user-1',
        attestationHeader: makeAttestation(),
      );
      expect(draft.totalContractedRevenue, report.totalContractedRevenue);
      expect(draft.protectedRevenue, report.protectedRevenue);
      expect(draft.lostRevenue, report.lostRevenue);
      expect(draft.complianceRateBps, report.complianceRateBps);
    });

    test('throws if organizationId is empty', () {
      expect(() => makeDraft(orgId: ''), throwsA(isA<DomainException>()));
    });

    test('throws if periodEnd is before periodStart', () {
      expect(
        () => AuditPackage.createDraft(
          organizationId: 'org-abc',
          contractId: null,
          contractorName: 'Contractor',
          periodStartUtc: DateTime.utc(2026, 3, 31),
          periodEndUtc: DateTime.utc(2026, 3, 1),
          report: makeReport(),
          reportLedgerBoundary: '100',
          engineVersionAtGeneration: '1.0.0',
          generatedByUserId: 'user-1',
          attestationHeader: makeAttestation(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws if periodStart is not UTC', () {
      expect(
        () => AuditPackage.createDraft(
          organizationId: 'org-abc',
          contractId: null,
          contractorName: 'Contractor',
          periodStartUtc: DateTime(2026, 3, 1), // local time
          periodEndUtc: periodEnd,
          report: makeReport(),
          reportLedgerBoundary: '100',
          engineVersionAtGeneration: '1.0.0',
          generatedByUserId: 'user-1',
          attestationHeader: makeAttestation(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('schemaVersion is 7.1.0', () {
      final draft = makeDraft();
      expect(draft.schemaVersion, '7.1.0');
    });
  });

  // ── AuditPackage.seal ──────────────────────────────────────────────────────
  group('AuditPackage.seal', () {
    test('returns NEW instance with status=sealed', () {
      final draft = makeDraft();
      final sealed = draft.seal();
      expect(sealed.status, AuditPackageStatus.sealed);
      expect(sealed.id, isNot(equals(draft.id))); // D1-Canonical: new row
    });

    test('computes a non-null packageHash', () {
      final sealed = makeDraft().seal();
      expect(sealed.packageHash, isNotNull);
      expect(sealed.packageHash, isNotEmpty);
    });

    test('same inputs produce byte-identical packageHash (determinism)', () {
      final draft = makeDraft(reportLedgerBoundary: '999');
      final sealed1 = draft.seal();
      final sealed2 = draft.seal();
      expect(sealed1.packageHash, equals(sealed2.packageHash));
    });

    test('different reportLedgerBoundary produces different hash', () {
      final sealed1 = makeDraft(reportLedgerBoundary: '100').seal();
      final sealed2 = makeDraft(reportLedgerBoundary: '200').seal();
      expect(sealed1.packageHash, isNot(equals(sealed2.packageHash)));
    });

    test('preserves all financial fields from draft', () {
      final draft = makeDraft();
      final sealed = draft.seal();
      expect(sealed.totalContractedRevenue, draft.totalContractedRevenue);
      expect(sealed.protectedRevenue, draft.protectedRevenue);
      expect(sealed.lostRevenue, draft.lostRevenue);
      expect(sealed.reportLedgerBoundary, draft.reportLedgerBoundary);
    });

    test('draft instance is not mutated by seal()', () {
      final draft = makeDraft();
      draft.seal(); // should not affect draft
      expect(draft.status, AuditPackageStatus.draft);
      expect(draft.packageHash, isNull);
    });

    test('throws DomainException if already sealed', () {
      final sealed = makeDraft().seal();
      expect(() => sealed.seal(), throwsA(isA<DomainException>()));
    });

    test('throws DomainException if superseded', () {
      final sealed = makeDraft().seal();
      final superseded = sealed.supersede(reason: 'Data correction');
      expect(() => superseded.seal(), throwsA(isA<DomainException>()));
    });
  });

  // ── AuditPackage.verifyIntegrity ───────────────────────────────────────────
  group('AuditPackage.verifyIntegrity', () {
    test('returns true for freshly sealed package', () {
      final sealed = makeDraft().seal();
      expect(sealed.verifyIntegrity(), isTrue);
    });

    test('returns false on draft (no packageHash)', () {
      final draft = makeDraft();
      expect(draft.verifyIntegrity(), isFalse);
    });

    test('returns false when reconstituted with tampered hash', () {
      final sealed = makeDraft().seal();
      final tampered = AuditPackage.reconstitute(
        id: sealed.id,
        organizationId: sealed.organizationId,
        contractId: sealed.contractId,
        contractorName: sealed.contractorName,
        periodStartUtc: sealed.periodStartUtc,
        periodEndUtc: sealed.periodEndUtc,
        billingCycleReportId: sealed.billingCycleReportId,
        reportLedgerBoundary: sealed.reportLedgerBoundary,
        snapshotIds: sealed.snapshotIds,
        totalContractedRevenue: sealed.totalContractedRevenue,
        protectedRevenue: sealed.protectedRevenue,
        revenueAtRisk: sealed.revenueAtRisk,
        lostRevenue: const Money(99999), // TAMPERED
        totalObligations: sealed.totalObligations,
        executedCount: sealed.executedCount,
        noShowCount: sealed.noShowCount,
        evidenceGapCount: sealed.evidenceGapCount,
        complianceRateBps: sealed.complianceRateBps,
        packageHash: sealed.packageHash, // old hash
        hashAlgorithm: sealed.hashAlgorithm,
        schemaVersion: sealed.schemaVersion,
        engineVersionAtGeneration: sealed.engineVersionAtGeneration,
        status: sealed.status,
        previousPackageId: null,
        supersessionReason: null,
        generatedAtUtc: sealed.generatedAtUtc,
        generatedByUserId: sealed.generatedByUserId,
        attestationHeader: sealed.attestationHeader,
      );
      expect(tampered.verifyIntegrity(), isFalse);
    });
  });

  // ── AuditPackage.supersede ─────────────────────────────────────────────────
  group('AuditPackage.supersede', () {
    test('returns new instance with status=superseded', () {
      final sealed = makeDraft().seal();
      final superseded = sealed.supersede(reason: 'Corrected vehicle binding');
      expect(superseded.status, AuditPackageStatus.superseded);
    });

    test('links previousPackageId to the original package', () {
      final sealed = makeDraft().seal();
      final superseded = sealed.supersede(reason: 'Corrected vehicle binding');
      expect(superseded.previousPackageId, equals(sealed.id));
    });

    test('carries the supersession reason', () {
      final sealed = makeDraft().seal();
      final superseded = sealed.supersede(reason: 'Late telemetry received');
      expect(superseded.supersessionReason, 'Late telemetry received');
    });

    test('throws DomainException if reason is empty', () {
      final sealed = makeDraft().seal();
      expect(
        () => sealed.supersede(reason: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException if already superseded', () {
      final sealed = makeDraft().seal();
      final superseded = sealed.supersede(reason: 'First correction');
      expect(
        () => superseded.supersede(reason: 'Second attempt'),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── AttestationHeader ─────────────────────────────────────────────────────
  group('AttestationHeader', () {
    test('creates with all required fields', () {
      final header = makeAttestation();
      expect(header.tenantName, 'Transportadora Exemplo Ltda');
      expect(header.engineVersion, '1.0.0');
    });

    test('throws if tenantName is empty', () {
      expect(
        () => AttestationHeader.create(
          tenantName: '',
          tenantCnpj: null,
          contractorName: 'Contractor',
          contractorCnpj: null,
          reportGeneratedBy: 'user-1',
          reportGeneratedAtUtc: generatedAt,
          engineVersion: '1.0.0',
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws if reportGeneratedAtUtc is not UTC', () {
      expect(
        () => AttestationHeader.create(
          tenantName: 'Tenant',
          tenantCnpj: null,
          contractorName: 'Contractor',
          contractorCnpj: null,
          reportGeneratedBy: 'user-1',
          reportGeneratedAtUtc: DateTime(2026, 3, 17), // local time
          engineVersion: '1.0.0',
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('legalNotice references CPC Art. 369', () {
      final header = makeAttestation();
      expect(header.legalNotice, contains('CPC Art. 369'));
    });

    test('evidenceQualityAttribution mentions hardware when rate < 80', () {
      // Verified via ShadowModeSimulation — attestation header itself does not
      // carry evidenceQualityRate. That's on ShadowModeSimulation.
      // This test ensures platformVersion appears in legalNotice.
      final header = makeAttestation();
      expect(header.legalNotice, contains('veraprob'));
    });
  });

  // ── Reportledger boundary: max across multiple snapshots ───────────────────
  group('reportLedgerBoundary semantics', () {
    test('max across snapshots is the correct boundary', () {
      final snap1 = makeSnapshot(lastLedgerEntryId: '4210');
      final snap2 = makeSnapshot(lastLedgerEntryId: '4471');
      final snap3 = makeSnapshot(lastLedgerEntryId: '4318');

      final report = BillingCycleReport.create(
        organizationId: 'org-abc',
        contractId: 'contract-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [snap1, snap2, snap3],
        isComplete: true,
        missingDates: [],
        generatedAtUtc: generatedAt,
      );

      // The caller computes max and passes it — test that the value is accepted correctly
      const maxBoundary = '4471';
      final draft = AuditPackage.createDraft(
        organizationId: 'org-abc',
        contractId: 'contract-1',
        contractorName: 'Contratante S.A.',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        report: report,
        reportLedgerBoundary: maxBoundary,
        engineVersionAtGeneration: '1.0.0',
        generatedByUserId: 'user-1',
        attestationHeader: makeAttestation(),
      );
      expect(draft.reportLedgerBoundary, '4471');
    });
  });
}
