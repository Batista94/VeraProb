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
  static const PdfColor _amber = PdfColor.fromInt(
    0xFFB45309,
  ); // Dark Amber/Orange for high contrast on white (4.5:1)
  static const PdfColor _amberFaint = PdfColor.fromInt(0xFFFEF3C7);
  static const PdfColor _amberWatermark = PdfColor.fromInt(
    0x10FFD0A0,
  ); // 6% alpha — degrades to soft pastel on alpha-ignorant viewers
  static const PdfColor _rose = PdfColor.fromInt(
    0xFFBE123C,
  ); // Deep Crimson Red for high contrast (4.5:1)
  static const PdfColor _roseFaint = PdfColor.fromInt(0xFFFFE4E6);
  static const PdfColor _roseWatermark = PdfColor.fromInt(
    0x10FFA0A0,
  ); // 6% alpha
  static const PdfColor _teal = PdfColor.fromInt(
    0xFF0F766E,
  ); // Deep Teal for high contrast (4.5:1)
  static const PdfColor _tealFaint = PdfColor.fromInt(0xFFCCFBF1);
  static const PdfColor _tealWatermark = PdfColor.fromInt(
    0x10A0E0D0,
  ); // 6% alpha
  static const PdfColor _darkGreen = PdfColor.fromInt(
    0xFF065F46,
  ); // Already high contrast dark green
  static const PdfColor _darkGreenFaint = PdfColor.fromInt(0xFFD1FAE5);
  static const PdfColor _darkGreenWatermark = PdfColor.fromInt(
    0x10A0D0A0,
  ); // 6% alpha

  @override
  Future<List<int>> generateDossier(ForensicDossier dossier) async {
    try {
      // compress: false — forensic dossiers remain raw-inspectable (INV-9).
      // Uncompressed content streams allow SHA-256 verification without a PDF reader.
      final doc = pw.Document(compress: false);
      final hash = dossier.computeHash();
      final generatedAt = DateTime.now().toUtc();
      final sealed = dossier.isSealed;

      final theme = _getThemeTokens(dossier.classification);

      // Citable document id — eventId when present, else the short verdict/custody
      // seal. No schema change; reuses data already sealed in the dossier.
      final dossierId =
          dossier.ledgerEntry.eventId ??
          (dossier.verdictSealHash ?? hash).substring(0, 12).toUpperCase();

      doc.addPage(
        pw.MultiPage(
          pageTheme: _buildPageTheme(theme.watermarkText, theme.watermarkColor),
          footer: (_) => _buildFooter(hash, generatedAt),
          build: (_) => _buildContent(
            dossier: dossier,
            dossierId: dossierId,
            generatedAt: generatedAt,
            hash: hash,
            sealed: sealed,
            accent: theme.accent,
            faint: theme.faint,
            watermarkText: theme.watermarkText,
          ),
        ),
      );

      return doc.save();
    } catch (e) {
      throw PdfGenerationException(e.toString());
    }
  }

  // ── Extracted Builders ─────────────────────────────────────────────────────

  ({
    PdfColor accent,
    PdfColor faint,
    PdfColor watermarkColor,
    String watermarkText,
  })
  _getThemeTokens(DossierClassification classification) {
    return switch (classification) {
      DossierClassification.preliminary => (
        accent: _amber,
        faint: _amberFaint,
        watermarkColor: _amberWatermark,
        watermarkText: 'PRELIMINAR - EM ANÁLISE',
      ),
      DossierClassification.applied => (
        accent: _rose,
        faint: _roseFaint,
        watermarkColor: _roseWatermark,
        watermarkText: 'INFRAÇÃO CONFIRMADA',
      ),
      DossierClassification.annulled => (
        accent: _teal,
        faint: _tealFaint,
        watermarkColor: _tealWatermark,
        watermarkText: 'INFRAÇÃO ANULADA',
      ),
      DossierClassification.acknowledged => (
        accent: _darkGreen,
        faint: _darkGreenFaint,
        watermarkColor: _darkGreenWatermark,
        watermarkText: 'VEREDITO SELADO - DE ACORDO',
      ),
    };
  }

  pw.Widget _buildFooter(String hash, DateTime generatedAt) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Documento gerado eletronicamente. Validade jurídica garantida por '
            'selo criptográfico SHA-256. Dispensada assinatura manual.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'SHA-256: $hash  |  Gerado em: ${generatedAt.toIso8601String()} UTC',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.PageTheme _buildPageTheme(String watermarkText, PdfColor watermarkColor) {
    // Full-page diagonal watermark — the unmistakable "reality stamp" of the
    // document's lifecycle state, painted behind the forensic body.
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      buildBackground: (_) => pw.FullPage(
        ignoreMargins: true,
        child: pw.Watermark.text(
          watermarkText,
          angle: math.pi / 5,
          style: pw.TextStyle(
            color: watermarkColor,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  List<pw.Widget> _buildContent({
    required ForensicDossier dossier,
    required String dossierId,
    required DateTime generatedAt,
    required String hash,
    required bool sealed,
    required PdfColor accent,
    required PdfColor faint,
    required String watermarkText,
  }) {
    final entry = dossier.ledgerEntry;
    return [
      // ── Header ────────────────────────────────────────────────────
      _sectionHeader('DOSSIÊ FORENSE - VeraProb'),
      pw.SizedBox(height: 4),
      pw.Text(
        'Dossiê Nº: $dossierId',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
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
      _renderImageOrFallback(
        dossier.mapImageBytes,
        fallback: 'Sem coordenadas registradas para esta ocorrência.',
      ),
      pw.SizedBox(height: 12),

      // ── Defesa do Transportador ───────────────────────────────────
      _buildCarrierDefenseSection(dossier, sealed),

      // ── Veredito do Auditor (sealed only, INV-21) ─────────────────
      if (sealed) ..._verdictSection(dossier),

      // ── Resumo Financeiro ──────────────────────────────────────────
      _buildFinancialSummarySection(dossier),

      // ── Cadeia de Custódia (INV-9) ─────────────────────────────────
      _buildChainOfCustodySection(hash, sealed),
    ];
  }

  pw.Widget _buildCarrierDefenseSection(ForensicDossier dossier, bool sealed) {
    // Sealed: the carrier's submitted evidence is part of the record.
    // Preliminary: the defense window is still open — the document MUST
    // say so explicitly so it is never used to close a billing early.
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionHeader('DEFESA DO TRANSPORTADOR'),
        pw.SizedBox(height: 4),
        if (dossier.classification == DossierClassification.annulled)
          // FRENTE 2: Fallback de texto para status 'rejected' / 'annulled' (Dossiê Forense)
          pw.Text(
            'ISENTADO - Infração anulada pelo auditor. Não há cobrança de multa ou necessidade de envio de defesa pelo transportador.',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _teal,
            ),
          )
        else if (sealed)
          _renderImageOrFallback(
            dossier.telegramImageBytes,
            fallback:
                'Transportador não anexou evidência de defesa para esta ocorrência.',
          )
        else
          pw.Text(
            'PENDENTE - documento preliminar emitido antes da defesa do '
            'transportador. Não utilize para fechar faturamento.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _buildFinancialSummarySection(ForensicDossier dossier) {
    // INV-21: an annulled verdict has ZERO financial impact. The original
    // amount stays sealed in the hash, but the rendered summary MUST show
    // R$ 0,00 so the carrier is never billed off an isentada dossier.
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionHeader('RESUMO FINANCEIRO'),
        pw.SizedBox(height: 4),
        if (dossier.classification == DossierClassification.annulled)
          _labelValue(
            'Impacto Financeiro',
            'R\$ 0,00 (multa original de '
                'R\$ ${(dossier.savingsCents / 100).toStringAsFixed(2)} isentada)',
          )
        else
          _labelValue(
            'Impacto Financeiro',
            'R\$ ${(dossier.savingsCents / 100).toStringAsFixed(2)}',
          ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _buildChainOfCustodySection(String hash, bool sealed) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
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
    );
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
            pw.SizedBox(height: 4),
            pw.Text(
              'Resultado: $outcomeLabel',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
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

  /// Renders image bytes as a [pw.Image], falling back to a contextual message
  /// (never a bare 'N/D') when:
  ///   - bytes is null or empty
  ///   - bytes are not a valid/decodable image format (e.g. during testing)
  pw.Widget _renderImageOrFallback(
    List<int>? bytes, {
    required String fallback,
  }) {
    if (bytes == null || bytes.isEmpty) {
      return pw.Text(
        fallback,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      );
    }
    try {
      return pw.Image(
        pw.MemoryImage(Uint8List.fromList(bytes)),
        height: 200,
        fit: pw.BoxFit.contain,
      );
    } catch (_) {
      // Invalid or undecodable image data — render contextual placeholder.
      return pw.Text(
        fallback,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
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
