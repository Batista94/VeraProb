import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:veraprob/domain/reporting/forensic_dossier.dart';
import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';

/// Concrete implementation of [IForensicPdfGenerator] using package:pdf.
///
/// INV-6: All timestamps rendered in UTC.
/// INV-9: SHA-256 hash (pre-computed by [ForensicDossier.computeHash])
///        printed in the footer of every page.
class PdfDossierGenerator implements IForensicPdfGenerator {
  @override
  Future<List<int>> generateDossier(ForensicDossier dossier) async {
    try {
      // compress: false — forensic dossiers remain raw-inspectable (INV-9).
      // Uncompressed content streams allow SHA-256 verification without a PDF reader.
      final doc = pw.Document(compress: false);
      final hash = dossier.computeHash();
      final entry = dossier.ledgerEntry;
      final generatedAt = DateTime.now().toUtc();

      final footer = pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(
          'SHA-256: $hash  |  Gerado em: ${generatedAt.toIso8601String()} UTC',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      );

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          footer: (_) => footer,
          build: (_) => [
            // ── Header ────────────────────────────────────────────────────
            _sectionHeader('DOSSIÊ FORENSE — VeraProb'),
            pw.SizedBox(height: 4),
            pw.Text(
              'Gerado em: ${generatedAt.toIso8601String()} UTC',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.Divider(),
            pw.SizedBox(height: 8),

            // ── Dados do Evento ────────────────────────────────────────────
            _sectionHeader('DADOS DO EVENTO'),
            pw.SizedBox(height: 4),
            _labelValue('Contrato', entry.contractId),
            _labelValue('Org ID', entry.organizationId),
            _labelValue('Data UTC', entry.occurredAtUtc.toIso8601String()),
            _labelValue('Tipo', entry.type),
            pw.SizedBox(height: 12),

            // ── Mapa da Ocorrência ─────────────────────────────────────────
            _sectionHeader('MAPA DA OCORRÊNCIA'),
            pw.SizedBox(height: 4),
            _renderImageOrFallback(dossier.mapImageBytes),
            pw.SizedBox(height: 12),

            // ── Evidência Fotográfica (Telegram) ──────────────────────────
            _sectionHeader('EVIDÊNCIA FOTOGRÁFICA (Telegram)'),
            pw.SizedBox(height: 4),
            _renderImageOrFallback(dossier.telegramImageBytes),
            pw.SizedBox(height: 12),

            // ── Resumo Financeiro ──────────────────────────────────────────
            _sectionHeader('RESUMO FINANCEIRO'),
            pw.SizedBox(height: 4),
            _labelValue(
              'Savings BRL',
              'R\$ ${(dossier.savingsCents / 100).toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 12),

            // ── Cadeia de Custódia (INV-9) ─────────────────────────────────
            _sectionHeader('CADEIA DE CUSTÓDIA (INV-9)'),
            pw.SizedBox(height: 4),
            pw.Text('SHA-256: $hash', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 4),
            pw.Text(
              'Este hash foi computado sobre: eventId, organizationId, '
              'contractId, occurredAtUtc, payload, savingsCents, '
              'bytes do mapa estático e bytes da evidência Telegram (quando presentes).',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
      );

      return doc.save();
    } catch (e) {
      throw PdfGenerationException(e.toString());
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Renders image bytes as a [pw.Image], falling back to 'N/D' text when:
  ///   - bytes is null or empty
  ///   - bytes are not a valid/decodable image format (e.g. during testing)
  pw.Widget _renderImageOrFallback(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return pw.Text(
        'N/D',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
      );
    }
    try {
      return pw.Image(
        pw.MemoryImage(Uint8List.fromList(bytes)),
        height: 200,
        fit: pw.BoxFit.contain,
      );
    } catch (_) {
      // Invalid or undecodable image data — render placeholder.
      return pw.Text(
        'N/D',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
      );
    }
  }

  pw.Widget _sectionHeader(String text) => pw.Text(
    text,
    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
  );

  pw.Widget _labelValue(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 120,
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
}
