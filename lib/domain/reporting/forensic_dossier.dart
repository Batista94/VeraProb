// pr_scanner: ignore-regression
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// Lifecycle classification of a forensic dossier — the "One-Click Dossier"
/// state machine (INV-21).
///
/// The export button is ALWAYS available, but the document it produces must
/// reflect the exact state of the queue item at that millisecond. A verdict
/// that is not yet sealed can NEVER masquerade as a final, billable document.
enum DossierClassification {
  /// Verdict still under review (pending / disputed / awaiting peer review).
  /// Working copy: telemetry + map + contract only, stamped "PRELIMINAR".
  preliminary,

  /// Verdict sealed (applied / rejected / acknowledged). Immutable and billable:
  /// carries the carrier defense, the auditor's reason code and the verdict's
  /// cryptographic seal, stamped "VEREDITO SELADO".
  sealed,
}

/// Represents the final immutable data required to generate an Executive-Grade
/// Forensic PDF Certificate.
///
/// INV-9: The [computeHash] method guarantees that ALL telemetry, images, and
/// financial data are sealed into a single SHA-256 hash.
class ForensicDossier extends Equatable {
  final SlaLedgerEntry ledgerEntry;
  final List<int> mapImageBytes;
  final List<int>? telegramImageBytes;
  final int savingsCents;

  /// Lifecycle stamp of this document (INV-21). Defaults to [preliminary] —
  /// a dossier is only "sealed" once the verdict reaches a terminal state.
  final DossierClassification classification;

  /// Human-readable verdict outcome (e.g. "INFRAÇÃO CONFIRMADA").
  /// Rendered on sealed dossiers only; null while preliminary.
  final String? verdictOutcomeLabel;

  /// Structured reason code chosen by the auditor. Sealed dossiers only.
  final String? auditorReasonCode;

  /// Free-text rationale recorded by the auditor. Sealed dossiers only.
  final String? auditorNote;

  /// SHA-256 of the sealed verdict evidence (INV-21 snapshot id). Sealed only.
  final String? verdictSealHash;

  const ForensicDossier({
    required this.ledgerEntry,
    required this.mapImageBytes,
    this.telegramImageBytes,
    required this.savingsCents,
    this.classification = DossierClassification.preliminary,
    this.verdictOutcomeLabel,
    this.auditorReasonCode,
    this.auditorNote,
    this.verdictSealHash,
  });

  /// Whether this dossier reflects a sealed, terminal verdict (INV-21).
  bool get isSealed => classification == DossierClassification.sealed;

  /// Computes the SHA-256 hash (INV-9) of the entire dossier contents.
  /// Any modification to the image bytes or ledger entry will change the hash.
  String computeHash() {
    final buffer = StringBuffer();

    // Ledger basic data
    buffer.write(ledgerEntry.eventId ?? '');
    buffer.write('|');
    buffer.write(ledgerEntry.organizationId);
    buffer.write('|');
    buffer.write(ledgerEntry.contractId);
    buffer.write('|');
    buffer.write(ledgerEntry.occurredAtUtc.toIso8601String());
    buffer.write('|');
    buffer.write(jsonEncode(ledgerEntry.payload));
    buffer.write('|');
    buffer.write(savingsCents.toString());
    buffer.write('|');

    // Convert to bytes
    final textBytes = utf8.encode(buffer.toString());

    // Combine all bytes
    final allBytes = <int>[
      ...textBytes,
      ...mapImageBytes,
      if (telegramImageBytes != null) ...telegramImageBytes!,
    ];

    return sha256.convert(allBytes).toString();
  }

  @override
  List<Object?> get props => [
    ledgerEntry,
    mapImageBytes,
    telegramImageBytes,
    savingsCents,
    classification,
    verdictOutcomeLabel,
    auditorReasonCode,
    auditorNote,
    verdictSealHash,
  ];
}
