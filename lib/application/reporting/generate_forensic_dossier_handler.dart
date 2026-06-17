import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/reporting/forensic_dossier.dart';
import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';
import 'package:veraprob/domain/reporting/i_static_map_service.dart';
import 'package:veraprob/domain/reporting/i_pdf_dossier_log_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';

class GenerateForensicDossierCommand {
  final String sessionId;
  final String operatorId;
  final String jwtOrganizationId;
  final String requestedOrganizationId;
  final SlaLedgerEntry ledgerEntry;
  final int savingsCents;
  final num mapLat;
  final num mapLng;
  final List<int>? telegramImageBytes;

  /// One-Click Dossier state machine: identifies the verdict status
  /// (applied / annulled / acknowledged). Drives the specific taxonomy stamp
  /// and the sealed-only sections. `preliminary` produces a "PRELIMINAR" document.
  final DossierClassification classification;

  /// Sealed-only metadata mirroring the exact verdict state (INV-21).
  final String? verdictOutcomeLabel;
  final String? auditorReasonCode;
  final String? auditorNote;
  final String? verdictSealHash;

  const GenerateForensicDossierCommand({
    required this.sessionId,
    required this.operatorId,
    required this.jwtOrganizationId,
    required this.requestedOrganizationId,
    required this.ledgerEntry,
    required this.savingsCents,
    required this.mapLat,
    required this.mapLng,
    this.telegramImageBytes,
    this.classification = DossierClassification.preliminary,
    this.verdictOutcomeLabel,
    this.auditorReasonCode,
    this.auditorNote,
    this.verdictSealHash,
  });
}

class GenerateForensicDossierHandler {
  final IStaticMapService _staticMapService;
  final IForensicPdfGenerator _pdfGenerator;
  final IPdfDossierLogRepository _logRepository;
  final TenantValidationService _tenantValidationService;

  GenerateForensicDossierHandler(
    this._staticMapService,
    this._pdfGenerator,
    this._logRepository,
    this._tenantValidationService,
  );

  /// Orchestrates the forensic dossier generation.
  ///
  /// INV-9: Hash computed and logged AFTER PDF is successfully generated —
  /// preventing phantom custody entries on PDF failure.
  Future<List<int>> handle(GenerateForensicDossierCommand command) async {
    // 1. Fail-Fast Tenant Validation (INV-1 / INV-22)
    await _tenantValidationService.assertTenantMatches(
      payloadOrgId: command.requestedOrganizationId,
      sessionId: command.sessionId,
    );

    if (command.jwtOrganizationId != command.requestedOrganizationId ||
        command.jwtOrganizationId != command.ledgerEntry.organizationId) {
      throw SovereigntyViolationException(
        payloadOrgId: command.requestedOrganizationId,
        jwtOrgId: command.jwtOrganizationId,
        message:
            'Tenant isolation violation in GenerateForensicDossierHandler.',
      );
    }

    // 2. Guard: entryId must be a valid UUID string (INV-10)
    final entryId =
        command.ledgerEntry.eventId ?? command.ledgerEntry.id?.toString();
    if (entryId == null) {
      throw const IntegrityException(
        'SlaLedgerEntry must have eventId or id to generate dossier',
        field: 'ledgerEntry',
      );
    }

    // 3. MapTiler Static API capture — best-effort enrichment ONLY.
    // A transient map outage must NEVER deny the operator their dossier (Tier-1
    // availability — the export button is always actionable). The document
    // degrades to a "map unavailable" placeholder instead of failing; the
    // SHA-256 custody seal still covers exactly the bytes that were embedded
    // (INV-9), so the certificate never lies about what it contains.
    List<int> mapImageBytes;
    try {
      mapImageBytes = await _staticMapService.getStaticMap(
        lat: command.mapLat,
        lng: command.mapLng,
        zoom: 16,
      );
    } catch (_) {
      mapImageBytes = const <int>[];
    }

    try {
      // 4. Assemble Domain Entity — stamped with the exact queue state (INV-21).
      final dossier = ForensicDossier(
        ledgerEntry: command.ledgerEntry,
        mapImageBytes: mapImageBytes,
        telegramImageBytes: command.telegramImageBytes,
        savingsCents: command.savingsCents,
        classification: command.classification,
        verdictOutcomeLabel: command.verdictOutcomeLabel,
        auditorReasonCode: command.auditorReasonCode,
        auditorNote: command.auditorNote,
        verdictSealHash: command.verdictSealHash,
      );

      // 5. Generate PDF via Infrastructure Port
      final pdfBytes = await _pdfGenerator.generateDossier(dossier);

      // 6. Compute Hash (INV-9) — uses same dossier that produced the PDF
      final dossierHash = dossier.computeHash();

      // 7. Cadeia de Custódia Híbrida — log AFTER successful PDF generation
      await _logRepository.logGeneration(
        organizationId: command.jwtOrganizationId,
        slaLedgerEntryId: entryId,
        documentHash: dossierHash,
        operatorId: command.operatorId,
      );

      return pdfBytes;
    } on SovereigntyViolationException {
      rethrow;
    } catch (e) {
      throw IntegrityException(
        'Failed to generate forensic dossier: ${e.toString().trim()}',
      );
    }
  }
}
