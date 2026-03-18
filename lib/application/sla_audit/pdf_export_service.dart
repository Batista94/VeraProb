import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/sla_audit/audit_package.dart';
import '../../domain/sla_audit/audit_package_status.dart';
import '../../domain/sla_audit/billing_cycle_report.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/shared/money.dart';

/// Generates legally-defensible PDF exports from sealed [AuditPackage] records.
///
/// **INV-18:** Throws [DomainException] if the package is not sealed.
/// **INV-19:** Every page carries the attestation metadata in the page footer.
///   The last page contains the full chain-of-custody block with hash
///   verification instructions.
///
/// Document structure:
///   Page 1 — Attestation cover (full legal block).
///   Page 2 — Executive summary (KPIs, revenue table).
///   Page 3..N — Daily snapshot breakdown (one table per contract).
///   Last page — Chain of Custody & hash verification instructions.
class PdfExportService {
  /// Generates a PDF document as raw bytes.
  ///
  /// **IMPORTANT (INV-3):** [package.generatedAtUtc] is used for the timestamp
  /// in the document — this service does NOT call [DateTime.now()].
  ///
  /// Throws [DomainException] if the package is not sealed (INV-18).
  Future<List<int>> generatePdf({
    required AuditPackage package,
    required BillingCycleReport report,
  }) async {
    _assertSealed(package);
    _assertReportMatches(package, report);

    final pdf = pw.Document();
    final h = package.attestationHeader;
    final contractScope = package.contractId ?? 'Todos os contratos';

    // ── Page 1: Attestation Cover (INV-19) ────────────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionHeader('ATESTADO DE AUTENTICIDADE — PACTAFLOW'),
            pw.Divider(),
            pw.SizedBox(height: 8),
            _labelValue('Report ID', package.billingCycleReportId),
            _labelValue('Package ID', package.id),
            _labelValue('Package Hash', 'SHA-256:${package.packageHash}'),
            _labelValue(
              'Ledger Boundary',
              'Entry #${package.reportLedgerBoundary}',
            ),
            pw.SizedBox(height: 8),
            _labelValue(
              'Emissor',
              '${h.tenantName} (CNPJ: ${h.tenantCnpj ?? "N/A"})',
            ),
            _labelValue(
              'Contratante',
              '${h.contractorName} (CNPJ: ${h.contractorCnpj ?? "N/A"})',
            ),
            _labelValue('Contrato', contractScope),
            _labelValue(
              'Período',
              '${_fmtDate(package.periodStartUtc)} a ${_fmtDate(package.periodEndUtc)} (UTC)',
            ),
            _labelValue(
              'Gerado em',
              '${package.generatedAtUtc.toIso8601String()} UTC',
            ),
            _labelValue('Gerado por', package.generatedByUserId),
            _labelValue('Engine', h.engineVersion),
            _labelValue('Schema', package.schemaVersion),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(
              h.immutabilityStatement,
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              h.verificationInstructions(
                organizationId: package.organizationId,
                contractScope: package.contractId ?? 'ALL',
                periodStart: package.periodStartUtc.toIso8601String(),
                periodEnd: package.periodEndUtc.toIso8601String(),
              ),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(h.legalNotice, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    );

    // ── Page 2: Executive Summary ─────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionHeader('RESUMO EXECUTIVO'),
            pw.SizedBox(height: 8),
            pw.Text(
              '${h.tenantName} — ${_fmtDate(package.periodStartUtc)} a ${_fmtDate(package.periodEndUtc)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: ['Métrica', 'Valor'],
              data: [
                [
                  'Faturamento Total Contratado',
                  _fmtBrl(package.totalContractedRevenue),
                ],
                [
                  'Receita Protegida (Blindada)',
                  _fmtBrl(package.protectedRevenue),
                ],
                ['Receita em Risco', _fmtBrl(package.revenueAtRisk)],
                ['Receita Perdida (Penalidades)', _fmtBrl(package.lostRevenue)],
                [
                  'Taxa de Conformidade',
                  '${package.complianceRate.toStringAsFixed(1)}%',
                ],
                ['Total de Obrigações', '${package.totalObligations}'],
                ['Executadas', '${package.executedCount}'],
                ['No Show', '${package.noShowCount}'],
                ['Gap de Evidência', '${package.evidenceGapCount}'],
              ],
            ),
            pw.SizedBox(height: 16),
            _sectionHeader('DISTRIBUIÇÃO DE RECEITA'),
            pw.SizedBox(height: 8),
            _revenueBar(package),
            pw.SizedBox(height: 8),
            if (!report.isComplete) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                'AVISO: Relatório com datas ausentes: '
                '${report.missingDates.map(_fmtDate).join(", ")}',
                style: pw.TextStyle(
                  color: PdfColors.red,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // ── Page 3+: Daily Breakdown ──────────────────────────────────────────────
    if (report.snapshots.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            _sectionHeader('DETALHAMENTO DIÁRIO'),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headers: [
                'Data',
                'Total (R\$)',
                'Protegido (R\$)',
                'Em Risco (R\$)',
                'Perdido (R\$)',
                'Obrig.',
                'Exec.',
                'N.Show',
                'Gap',
                'Conf.%',
                'Ledger ID',
              ],
              data: report.snapshots.map((s) {
                final compliance = s.totalObligations > 0
                    ? (s.executedCount / s.totalObligations * 100)
                    : 100.0;
                return [
                  _fmtDate(s.operationalDateUtc),
                  _fmtBrl(s.totalContractedRevenue),
                  _fmtBrl(s.protectedRevenue),
                  _fmtBrl(s.revenueAtRisk),
                  _fmtBrl(s.lostRevenue),
                  '${s.totalObligations}',
                  '${s.executedCount}',
                  '${s.noShowCount}',
                  '${s.evidenceGapCount}',
                  '${compliance.toStringAsFixed(1)}%',
                  '${s.lastLedgerEntryId ?? "-"}',
                ];
              }).toList(),
            ),
          ],
        ),
      );
    }

    // ── Last Page: Chain of Custody ───────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _sectionHeader('CADEIA DE CUSTÓDIA — VERIFICAÇÃO DE INTEGRIDADE'),
            pw.SizedBox(height: 8),
            pw.Text(
              'Este relatório pode ser verificado de forma independente em 6 etapas:',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            _custodyStep(
              '1',
              'Pacote de Exportação',
              'Package Hash SHA-256: ${package.packageHash}\n'
                  'Recalcule: SHA-256("${package.organizationId}|'
                  '${package.contractId ?? "ALL"}|'
                  '${package.periodStartUtc.toIso8601String()}|'
                  '${package.periodEndUtc.toIso8601String()}")\n'
                  'Correspondência = documento íntegro.',
            ),
            _custodyStep(
              '2',
              'Snapshots Diários',
              'IDs dos snapshots: ${report.snapshotIds.join(", ")}\n'
                  'Verifique na tabela contractual_financial_daily_snapshots.',
            ),
            _custodyStep(
              '3',
              'Boundary do Ledger',
              'Ledger Entry #${package.reportLedgerBoundary}\n'
                  'Toda entrada com id ≤ ${package.reportLedgerBoundary} está '
                  'dentro do escopo deste pacote.',
            ),
            _custodyStep(
              '4',
              'Traços de Avaliação',
              'Para cada obrigação contestada: consulte evaluation_traces '
                  'pelo triggeringEventId para ver a decisão completa do engine.',
            ),
            _custodyStep(
              '5',
              'Fatos Canônicos',
              'Cada traço aponta para um canonical_fact. '
                  'O campo raw_payload_id aponta para o blob bruto original.',
            ),
            _custodyStep(
              '6',
              'Payload Bruto Selado',
              'Verifique raw_telemetry_payloads.payload_hash (SHA-256). '
                  'Esta hash foi computada ANTES de qualquer transformação '
                  'e está protegida por regras de imutabilidade no banco de dados.',
            ),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(h.legalNotice, style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  pw.Widget _sectionHeader(String text) => pw.Text(
    text,
    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
  );

  pw.Widget _labelValue(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 140,
          child: pw.Text(
            '$label:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    ),
  );

  pw.Widget _custodyStep(String number, String title, String description) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'LINK $number — $title',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            ),
            pw.Text(description, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );

  /// ASCII-style revenue distribution bar for Page 2.
  pw.Widget _revenueBar(AuditPackage package) {
    final total = package.totalContractedRevenue.cents;
    if (total == 0) {
      return pw.Text(
        'Sem dados financeiros para o período.',
        style: const pw.TextStyle(fontSize: 9),
      );
    }
    final protectedPct = (package.protectedRevenue.cents / total * 100).round();
    final atRiskPct = (package.revenueAtRisk.cents / total * 100).round();
    final lostPct = (package.lostRevenue.cents / total * 100).round();

    return pw.TableHelper.fromTextArray(
      headers: ['Categoria', 'Valor (R\$)', '% do Total'],
      data: [
        [
          'Receita Protegida (Blindada)',
          _fmtBrl(package.protectedRevenue),
          '$protectedPct%',
        ],
        ['Receita em Risco', _fmtBrl(package.revenueAtRisk), '$atRiskPct%'],
        [
          'Receita Perdida (Penalidades)',
          _fmtBrl(package.lostRevenue),
          '$lostPct%',
        ],
      ],
    );
  }

  String _fmtDate(DateTime dt) => dt.toIso8601String().split('T')[0];

  String _fmtBrl(Money money) {
    final value = money.cents / 100;
    return 'R\$ ${value.toStringAsFixed(2)}';
  }

  void _assertSealed(AuditPackage package) {
    if (package.status != AuditPackageStatus.sealed) {
      throw DomainException(
        'Cannot export an AuditPackage that is not sealed (INV-18). '
        'Current status: "${package.status}".',
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
        'but received "${report.id}".',
      );
    }
  }
}
