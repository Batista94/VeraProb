/// Forensic Audit Signature: CX-05-v3.1 / Red Team ID 3
/// Security Guard: INV-7, INV-9, INV-10, INV-13, INV-15, INV-18, INV-28
/// Authorized By: VeraProb Council (Architect + QA/Sec + Senior)
///
/// Polyglot defence at ingestion: validates the FIRST 12 bytes of a payload
/// against the strict whitelist in [BinarySignatureRegistry] and rejects
/// declared-extension/actual-format divergence.
///
/// **INV-9 ordering:** This validator MUST be invoked BEFORE
/// `EvidenceIntegrityVerifier.verifyAll`. A polyglot file may produce a
/// "correct" SHA-256 yet still be a forged format — the seal is only
/// meaningful over a content type the engine accepts.
///
/// **INV-28 (Confidentiality):** Exception messages contain only labels,
/// MIME types, and the declared extension. NEVER raw bytes, matched
/// substrings, or buffer dumps.
library;

import 'package:veraprob/application/sla_audit/justification/binary_signature_registry.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

/// Validates that an evidence payload's Magic Bytes match the declared
/// extension's expected MIME type.
///
/// **Buffer chunking:** Reads exactly [BinarySignatureRegistry.maxHeaderBytes]
/// bytes via `EvidenceStorageReader.readRange` — never streams the full file
/// (Availability / OOM defence).
///
/// **Polyglot rejection:** If `declaredExtension` resolves to a MIME that
/// differs from the detected magic-byte MIME, throws
/// [ForensicViolationException] with `ForensicConfidence.high`.
///
/// **Strict offset:** Magic bytes MUST appear at the exact declared offset.
/// Leading null padding, header skipping, or partial matches are rejected.
///
/// **Performance:** O(headers × bytes_per_header) ≈ 60 byte comparisons after
/// a single network round-trip — sub-millisecond on the local check.
class BinarySignatureValidator {
  final EvidenceStorageReader _reader;

  /// Canonical extension → MIME map. Closed enumeration; unknown extensions
  /// fail fast (INV-10). Keys are stored without leading dot, lowercase.
  static const Map<String, String> _extensionToMime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'pdf': 'application/pdf',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
  };

  const BinarySignatureValidator(this._reader);

  /// Validates the file at [url] against [declaredExtension].
  ///
  /// Returns the resolved canonical MIME on success.
  ///
  /// Throws [ForensicViolationException] (high confidence) on:
  ///   - Unknown / empty / null-like declared extension.
  ///   - File shorter than [BinarySignatureRegistry.maxHeaderBytes].
  ///   - No signature match in the whitelist.
  ///   - Declared MIME ≠ detected MIME (polyglot).
  ///
  /// I/O failures from [EvidenceStorageReader.readRange] propagate as-is
  /// (network/storage errors are NOT forensic violations).
  Future<String> validate({
    required String url,
    required String declaredExtension,
  }) async {
    final expectedMime = _expectedMime(declaredExtension);
    if (expectedMime == null) {
      throw ForensicViolationException(
        message:
            '[BinarySignatureValidator] Declared extension '
            '"$declaredExtension" is not in the forensic whitelist.',
        evidenceUrl: url,
        confidence: ForensicConfidence.high,
      );
    }

    final header = await _reader.readRange(
      url: url,
      start: 0,
      length: BinarySignatureRegistry.maxHeaderBytes,
    );

    if (header.length < BinarySignatureRegistry.maxHeaderBytes) {
      throw ForensicViolationException(
        message:
            '[BinarySignatureValidator] Payload too short for header '
            'inspection: ${header.length} bytes received, '
            '${BinarySignatureRegistry.maxHeaderBytes} required. '
            'Declared extension: "$declaredExtension".',
        evidenceUrl: url,
        confidence: ForensicConfidence.high,
      );
    }

    final detected = BinarySignatureRegistry.matchSignature(header);
    if (detected == null) {
      throw ForensicViolationException(
        message:
            '[BinarySignatureValidator] No whitelist signature matched the '
            'payload header. Declared extension: "$declaredExtension". '
            'Expected MIME: "$expectedMime".',
        evidenceUrl: url,
        confidence: ForensicConfidence.high,
      );
    }

    if (detected.mimeType != expectedMime) {
      throw ForensicViolationException(
        message:
            '[BinarySignatureValidator] Polyglot detected: declared '
            'extension "$declaredExtension" (expected "$expectedMime") '
            'but payload header is "${detected.label}" '
            '("${detected.mimeType}").',
        evidenceUrl: url,
        confidence: ForensicConfidence.high,
      );
    }

    return detected.mimeType;
  }

  /// Resolves the canonical MIME for a declared extension. Returns `null`
  /// when the extension is empty, malformed, or outside the whitelist.
  ///
  /// Normalisation: strip leading dot, lowercase, take the LAST dot-segment
  /// (`.jpg.php` → `php` → unknown → reject — Red Team Case C).
  static String? _expectedMime(String declaredExtension) {
    if (declaredExtension.isEmpty) return null;
    final lower = declaredExtension.toLowerCase();
    final lastDot = lower.lastIndexOf('.');
    final tail = lastDot >= 0 ? lower.substring(lastDot + 1) : lower;
    if (tail.isEmpty) return null;
    return _extensionToMime[tail];
  }
}
