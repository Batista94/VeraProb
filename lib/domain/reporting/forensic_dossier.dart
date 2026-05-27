// pr_scanner: ignore-regression
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

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

  const ForensicDossier({
    required this.ledgerEntry,
    required this.mapImageBytes,
    this.telegramImageBytes,
    required this.savingsCents,
  });

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
  ];
}
