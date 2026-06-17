import 'dart:math' as math;
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
/// INV-21: the document mirrors the EXACT verdict state — a preliminary dossier
///         is watermarked "PRELIMINAR" and omits the carrier defense / sealed
///         verdict, so it can never be passed off as a billable certificate.
class PdfDossierGenerator implements IForensicPdfGenerator {
  static const PdfColor _amber = PdfColor.fromInt(0xFFFBBF24);
  // Watermark alpha = 0x26 ≈ 15% opacity
  static const PdfColor _amberFaint = PdfColor.fromInt(0x26FBBF24);
  static const PdfColor _rose = PdfColor.fromInt(0xFFF87171);
  static const PdfColor _roseFaint = PdfColor.fromInt(0x26F87171);
  static const PdfColor _teal = PdfColor.fromInt(0xFF2DD4BF);
  static const PdfColor _tealFaint = PdfColor.fromInt(0x262DD4BF);
  static const PdfColor _darkGreen = PdfColor.fromInt(0xFF065F46);
  static const PdfColor _darkGreenFaint = PdfColor.fromInt(0x26065F46);

  @override
  Future<List<int>> generateDossier(ForensicDossier dossier) async {
    try {
      // compress: false — forensic dossiers remain raw-inspectable (INV-9).
      // Uncompressed content streams allow SHA-256 verification without a PDF reader.
      final doc = pw.Document(compress: false);
      final hash = dossier.computeHash();
      final entry = dossier.ledgerEntry;
      final generatedAt = DateTime.now().toUtc();

      final sealed = dossier.isSealed;
      final (
        PdfColor accent,
        PdfColor faint,
        String watermarkText,
      ) = switch (dossier.classification) {
        DossierClassification.preliminary => (
          _amber,
          _amberFaint,
          'PRELIMINAR - EM ANÁLISE',
        ),
        DossierClassification.applied => (
          _rose,
          _roseFaint,
          'INFRAÇÃO CONFIRMADA',
        ),
        DossierClassification.annulled => (
          _teal,
          _tealFaint,
          'INFRAÇÃO ANULADA',
        ),
        DossierClassification.acknowledged => (
          _darkGreen,
          _darkGreenFaint,
          'VEREDITO SELADO - DE ACORDO',
        ),
      };

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

      // Full-page diagonal watermark — the unmistakable "reality stamp" of the
      // document's lifecycle state, painted behind the forensic body.
      final pageTheme = pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        buildBackground: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Watermark.text(
            watermarkText,
            angle: math.pi / 5,
            style: pw.TextStyle(color: faint, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );

      doc.addPage(
        pw.MultiPage(
          pageTheme: pageTheme,
          footer: (_) => footer,
          build: (_) => [
            // ── Header ────────────────────────────────────────────────────
            _sectionHeader('DOSSIÊ FORENSE - VeraProb'),
            pw.SizedBox(height: 4),
            pw.Text(
              'Gerado em: ${generatedAt.toIso8601String()} UTC',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),

            // ── Status banner (lifecycle reality) ─────────────────────────
            _statusBanner(
              sealed,
              accent,
              faint,
              watermarkText,
              dossier.verdictOutcomeLabel,
            ),
            pw.SizedBox(height: 12),

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

            // ── Defesa do Transportador ───────────────────────────────────
            // Sealed: the carrier's submitted evidence is part of the record.
            // Preliminary: the defense window is still open — the document MUST
            // say so explicitly so it is never used to close a billing early.
            _sectionHeader('DEFESA DO TRANSPORTADOR'),
            pw.SizedBox(height: 4),
            if (dossier.classification == DossierClassification.annulled)
              // INV-21: Anulada por deliberação interna — seção de defesa dispensada.
              pw.Text(
                'Dispensado - Infração anulada por deliberação interna.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              )
            else if (sealed)
              _renderImageOrFallback(dossier.telegramImageBytes)
            else
              pw.Text(
                'PENDENTE - documento preliminar emitido antes da defesa do '
                'transportador. Não utilize para fechar faturamento.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            pw.SizedBox(height: 12),

            // ── Veredito do Auditor (sealed only, INV-21) ─────────────────
            if (sealed) ..._verdictSection(dossier),

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
              sealed
                  ? 'Este hash foi computado sobre: eventId, organizationId, '
                        'contractId, occurredAtUtc, payload, savingsCents, '
                        'bytes do mapa estático e bytes da evidência Telegram (quando presentes).'
                  : 'Selo de custódia do SNAPSHOT PRELIMINAR atual - não é o selo '
                        'do veredito final. O selo definitivo é emitido apenas '
                        'quando a sanção é concluída (VEREDITO SELADO).',
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

  /// Coloured banner declaring the document's lifecycle state up front.
  pw.Widget _statusBanner(
    bool sealed,
    PdfColor accent,
    PdfColor faint,
    String watermarkText,
    String? outcomeLabel,
  ) {
    final title = sealed
        ? watermarkText
        : 'PRELIMINAR - EM ANÁLISE · SEM DEFESA DO TRANSPORTADOR';
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: faint,
        border: pw.Border.all(color: accent, width: 1),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
          if (sealed && outcomeLabel != null && outcomeLabel.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              'Resultado: $outcomeLabel',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
          ],
        ],
      ),
    );
  }

  /// Sealed-only block: the auditor's verdict, reason code and the verdict's
  /// own cryptographic seal (INV-21) — distinct from the snapshot custody hash.
  List<pw.Widget> _verdictSection(ForensicDossier dossier) {
    return [
      _sectionHeader('VEREDITO DO AUDITOR'),
      pw.SizedBox(height: 4),
      if (dossier.verdictOutcomeLabel != null)
        _labelValue('Resultado', dossier.verdictOutcomeLabel!),
      if (dossier.auditorReasonCode != null)
        _labelValue('Reason Code', dossier.auditorReasonCode!),
      if (dossier.auditorNote != null && dossier.auditorNote!.isNotEmpty)
        _labelValue('Justificativa', dossier.auditorNote!),
      if (dossier.verdictSealHash != null) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          'Selo Criptográfico do Veredito (INV-21):',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
        ),
        pw.Text(
          'SHA-256: ${dossier.verdictSealHash}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
      pw.SizedBox(height: 12),
    ];
  }

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
