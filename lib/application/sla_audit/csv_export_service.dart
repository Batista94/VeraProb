import '../../domain/sla_audit/audit_package.dart';
import '../../domain/sla_audit/audit_package_status.dart';
import '../../domain/sla_audit/billing_cycle_report.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/shared/money.dart';

/// Generates legally-defensible CSV exports from sealed [AuditPackage] records.
///
/// **INV-18:** Throws [DomainException] if the package is not sealed.
/// **INV-19:** Always prepends the canonical [AttestationHeader] as comment lines.
///
/// Output format:
/// - UTF-8 BOM (required for Excel compatibility in Brazil).
/// - `#`-prefixed comment lines containing the full attestation block.
/// - Semicolon-delimited data rows with both raw cents and formatted BRL columns.
class CsvExportService {
  static const String _bom = '\uFEFF'; // UTF-8 BOM for Excel compatibility

  /// Generates the CSV content for the given [package] and its [report].
  ///
  /// The [report] must be the [BillingCycleReport] whose ID matches
  /// [package.billingCycleReportId].
  ///
  /// Throws [DomainException] if:
  /// - The package is not [AuditPackageStatus.sealed] (INV-18).
  /// - The report ID does not match the package (integrity check).
  String generateCsv({
    required AuditPackage package,
    required BillingCycleReport report,
  }) {
    _assertSealed(package);
    _assertReportMatches(package, report);

    final buffer = StringBuffer();

    // UTF-8 BOM
    buffer.write(_bom);

    // ── Attestation header as comment block (INV-19) ─────────────────────────
    final h = package.attestationHeader;
    final contractScope = package.contractId ?? 'ALL';

    buffer.writeln('# ATTESTATION OF AUTHENTICITY — veraprob AUDIT EXPORT');
    buffer.writeln('# =====================================================');
    buffer.writeln('# Report ID:       ${package.billingCycleReportId}');
    buffer.writeln('# Package ID:      ${package.id}');
    buffer.writeln('# Package Hash:    SHA-256:${package.packageHash}');
    buffer.writeln('# Ledger Boundary: Entry #${package.reportLedgerBoundary}');
    buffer.writeln(
      '# Issuing Org:     ${h.tenantName} (CNPJ: ${h.tenantCnpj ?? "N/A"})',
    );
    buffer.writeln(
      '# Contractor:      ${h.contractorName} (CNPJ: ${h.contractorCnpj ?? "N/A"})',
    );
    buffer.writeln(
      '# Period:          ${package.periodStartUtc.toIso8601String()} to '
      '${package.periodEndUtc.toIso8601String()} UTC',
    );
    buffer.writeln(
      '# Generated:       ${package.generatedAtUtc.toIso8601String()} UTC',
    );
    buffer.writeln('#                  by ${package.generatedByUserId}');
    buffer.writeln('# Engine:          ${h.engineVersion}');
    buffer.writeln('# Schema:          ${package.schemaVersion}');
    buffer.writeln('#');
    buffer.writeln('# ${h.immutabilityStatement}');
    buffer.writeln('#');
    buffer.writeln(
      '# ${h.verificationInstructions(organizationId: package.organizationId, contractScope: contractScope, periodStart: package.periodStartUtc.toIso8601String(), periodEnd: package.periodEndUtc.toIso8601String())}',
    );
    buffer.writeln('#');
    buffer.writeln('# ${h.legalNotice}');
    buffer.writeln('# =====================================================');
    buffer.writeln('#');

    // ── Column headers ───────────────────────────────────────────────────────
    final headers = [
      'Data Operacional',
      'Faturamento Total (Cents)',
      'Faturamento Total (BRL)',
      'Receita Protegida (Cents)',
      'Receita Protegida (BRL)',
      'Receita em Risco (Cents)',
      'Receita em Risco (BRL)',
      'Perda Financeira (Cents)',
      'Perda Financeira (BRL)',
      'Obrigacoes Totais',
      'Executadas',
      'No Show',
      'Gap de Evidencia',
      'Conformidade %',
      'Ledger Boundary ID',
    ];
    _appendRow(buffer, headers);

    // ── Snapshot rows ─────────────────────────────────────────────────────────
    for (final s in report.snapshots) {
      final compliance = s.totalObligations > 0
          ? (s.executedCount / s.totalObligations * 100)
          : 100.0;
      _appendRow(buffer, [
        s.operationalDateUtc.toIso8601String().split('T')[0],
        s.totalContractedRevenue.cents,
        _formatBrl(s.totalContractedRevenue),
        s.protectedRevenue.cents,
        _formatBrl(s.protectedRevenue),
        s.revenueAtRisk.cents,
        _formatBrl(s.revenueAtRisk),
        s.lostRevenue.cents,
        _formatBrl(s.lostRevenue),
        s.totalObligations,
        s.executedCount,
        s.noShowCount,
        s.evidenceGapCount,
        compliance.toStringAsFixed(2),
        s.lastLedgerEntryId ?? '',
      ]);
    }

    // ── Totals row ────────────────────────────────────────────────────────────
    _appendRow(buffer, []);
    _appendRow(buffer, [
      'TOTAL PERIODO',
      package.totalContractedRevenue.cents,
      _formatBrl(package.totalContractedRevenue),
      package.protectedRevenue.cents,
      _formatBrl(package.protectedRevenue),
      package.revenueAtRisk.cents,
      _formatBrl(package.revenueAtRisk),
      package.lostRevenue.cents,
      _formatBrl(package.lostRevenue),
      package.totalObligations,
      package.executedCount,
      package.noShowCount,
      package.evidenceGapCount,
      (package.complianceRateBps / 100.0).toStringAsFixed(2),
      package.reportLedgerBoundary,
    ]);

    return buffer.toString();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _appendRow(StringBuffer buf, List<dynamic> fields) {
    for (int i = 0; i < fields.length; i++) {
      final raw = fields[i]?.toString() ?? '';
      // Escape semicolons, newlines and quotes per RFC 4180 (semicolon variant)
      if (raw.contains(';') || raw.contains('\n') || raw.contains('"')) {
        buf.write('"${raw.replaceAll('"', '""')}"');
      } else {
        buf.write(raw);
      }
      if (i < fields.length - 1) buf.write(';');
    }
    buf.write('\r\n');
  }

  String _formatBrl(Money money) {
    final value = money.cents / 100;
    return 'R\$ ${value.toStringAsFixed(2)}';
  }

  void _assertSealed(AuditPackage package) {
    if (package.status != AuditPackageStatus.sealed) {
      throw DomainException(
        'Cannot export an AuditPackage that is not sealed (INV-18). '
        'Current status: "${package.status}". Call AuditPackageService.createDraftAndSeal() first.',
      );
    }
    if (package.packageHash == null || package.packageHash!.isEmpty) {
      throw const DomainException(
        'Package is sealed but packageHash is missing — data integrity violation (INV-18).',
      );
    }
  }

  void _assertReportMatches(AuditPackage package, BillingCycleReport report) {
    if (report.id != package.billingCycleReportId) {
      throw DomainException(
        'Report ID mismatch: package expects "${package.billingCycleReportId}" '
        'but received "${report.id}". Provide the report that generated this package.',
      );
    }
  }
}
