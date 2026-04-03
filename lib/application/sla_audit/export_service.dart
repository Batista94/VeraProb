import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../application/shared/billing_cycle_view.dart';

/// Service responsible for generating deterministic exports in CSV and PDF formats.
class ExportService {
  /// Generates a deterministic CSV representation of the report.
  String generateCsv(BillingCycleView report) {
    final List<List<dynamic>> rows = [];

    // Header
    rows.add([
      'Data Operacional',
      'Faturamento Total (Cents)',
      'Receita Protegida (Cents)',
      'Receita em Risco (Cents)',
      'Perda (Cents)',
      'Obrigações Totais',
      'Executadas',
      'No Show',
      'Gap de Evidência',
      '% Risco',
      '% Perda',
    ]);

    // Snapshot rows
    for (final s in report.snapshots) {
      rows.add([
        s.operationalDateUtc.toIso8601String().split('T')[0],
        s.totalContractedRevenue,
        s.protectedRevenue,
        s.revenueAtRisk,
        s.lostRevenue,
        s.totalObligations,
        s.executedCount,
        s.noShowCount,
        s.evidenceGapCount,
        (s.riskPercentageBps / 100).toStringAsFixed(2),
        (s.lossPercentageBps / 100).toStringAsFixed(2),
      ]);
    }

    // Total row
    rows.add([]);
    rows.add([
      'TOTAL',
      report.totalContractedRevenue,
      report.protectedRevenue,
      report.revenueAtRisk,
      report.lostRevenue,
      report.totalObligations,
      report.executedCount,
      report.noShowCount,
      report.evidenceGapCount,
      (report.complianceRateBps / 100).toStringAsFixed(2),
      (100 - report.complianceRateBps / 100).toStringAsFixed(2),
    ]);

    final buffer = StringBuffer();
    for (final row in rows) {
      for (int i = 0; i < row.length; i++) {
        final field = row[i];
        final str = field?.toString() ?? '';
        if (str.contains(';') || str.contains('\n') || str.contains('"')) {
          buffer.write('"${str.replaceAll('"', '""')}"');
        } else {
          buffer.write(str);
        }
        if (i < row.length - 1) buffer.write(';');
      }
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  /// Generates a deterministic PDF representation of the report.
  Future<List<int>> generatePdf(BillingCycleView report) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Relatório de Ciclo de Faturamento - veraprob'),
          ),
          pw.Paragraph(text: 'Organização: ${report.organizationId}'),
          pw.Paragraph(
            text:
                'Período: ${report.periodStartUtc.toIso8601String().split('T')[0]} a ${report.periodEndUtc.toIso8601String().split('T')[0]}',
          ),
          pw.Paragraph(text: 'Contrato: ${report.contractId ?? "Todos"}'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: [
              'Data',
              'Total',
              'Protegido',
              'Risco',
              'Perda',
              'Compl. %',
            ],
            data: report.snapshots.map((s) {
              return [
                s.operationalDateUtc.toIso8601String().split('T')[0],
                _formatMoney(s.totalContractedRevenue),
                _formatMoney(s.protectedRevenue),
                _formatMoney(s.revenueAtRisk),
                _formatMoney(s.lostRevenue),
                '${(100 - s.lossPercentageBps / 100).toStringAsFixed(1)}%',
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.Header(level: 1, text: 'Consolidado'),
          pw.TableHelper.fromTextArray(
            headers: ['Métrica', 'Valor'],
            data: [
              [
                'Faturamento Total',
                _formatMoney(report.totalContractedRevenue),
              ],
              ['Receita Protegida', _formatMoney(report.protectedRevenue)],
              ['Receita em Risco', _formatMoney(report.revenueAtRisk)],
              ['Perda Financeira', _formatMoney(report.lostRevenue)],
              [
                'Taxa de Conformidade',
                '${(report.complianceRateBps / 100).toStringAsFixed(1)}%',
              ],
            ],
          ),
          if (!report.isComplete) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'AVISO: Relatório Incompleto',
              style: pw.TextStyle(
                color: PdfColors.red,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Bullet(
              text:
                  'Datas ausentes: ${report.missingDates.map((d) => d.toIso8601String().split('T')[0]).join(", ")}',
            ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  String _formatMoney(int cents) {
    return 'R\$ ${(cents / 100).toStringAsFixed(2)}';
  }
}
