/// Forensic Audit Signature: CX-05-v3.1 / Red Team ID 3
/// Security Guard: INV-7, INV-9, INV-10, INV-15, INV-18, INV-24, INV-28
/// Authorized By: VeraProb Council (Architect + QA/Sec + Senior)
library;

/// A typed Magic Byte signature for binary format detection.
///
/// Forensic identity of a file format: the byte pattern that MUST appear at
/// [offset] for a buffer to be considered a valid header. Some formats
/// (WebP) require a second non-contiguous match — represented by the optional
/// [secondaryOffset]/[secondaryBytes] pair (conjunctive AND, not fallback).
///
/// All fields are immutable. INV-7: no dynamic types.
typedef MagicSignature = ({
  String label,
  String mimeType,
  int offset,
  List<int> bytes,
  int? secondaryOffset,
  List<int>? secondaryBytes,
});

/// Centralised registry of forensic binary signatures.
///
/// Two distinct concerns, single source of truth:
///   1. [magicSignatures]: typed Magic Byte whitelist (format detection at
///      ingestion, INV-9 / INV-18).
///   2. [pattern]: regex for embedded script-injection payloads
///      (post-format payload scanning, used by `ContextualSignatureAnalyzer`).
///
/// Pure data + a single match helper. Performs zero I/O. INV-13 boundary safe.
class BinarySignatureRegistry {
  const BinarySignatureRegistry._();

  /// Maximum number of header bytes any signature ever inspects.
  ///
  /// Derived constant: WebP needs `RIFF` at offset 0 plus `WEBP` at offset 8
  /// (4 bytes) → 12. HEIC/HEIF need `ftyp<brand>` at offset 4 (8 bytes) → 12.
  /// All other formats fit within those bounds.
  ///
  /// Consumed by [BinarySignatureValidator] so the read length lives in one
  /// place.
  static const int maxHeaderBytes = 12;

  /// Strict whitelist. Order is irrelevant (no first-match-wins ambiguity:
  /// every signature is mutually exclusive at its declared offset).
  ///
  /// Brand-aware: HEIC accepts only `ftypheic`; HEIF accepts only `ftypmif1`.
  /// Variants such as `heix`, `hevc`, `msf1` are intentionally rejected
  /// (closed enumeration — Red Team Case A).
  static const List<MagicSignature> magicSignatures = [
    (
      label: 'JPEG',
      mimeType: 'image/jpeg',
      offset: 0,
      bytes: [0xFF, 0xD8, 0xFF],
      secondaryOffset: null,
      secondaryBytes: null,
    ),
    (
      label: 'PNG',
      mimeType: 'image/png',
      offset: 0,
      bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      secondaryOffset: null,
      secondaryBytes: null,
    ),
    (
      label: 'PDF',
      mimeType: 'application/pdf',
      offset: 0,
      bytes: [0x25, 0x50, 0x44, 0x46, 0x2D],
      secondaryOffset: null,
      secondaryBytes: null,
    ),
    (
      label: 'HEIC',
      mimeType: 'image/heic',
      offset: 4,
      bytes: [0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63],
      secondaryOffset: null,
      secondaryBytes: null,
    ),
    (
      label: 'HEIF',
      mimeType: 'image/heif',
      offset: 4,
      bytes: [0x66, 0x74, 0x79, 0x70, 0x6D, 0x69, 0x66, 0x31],
      secondaryOffset: null,
      secondaryBytes: null,
    ),
    (
      label: 'WebP',
      mimeType: 'image/webp',
      offset: 0,
      bytes: [0x52, 0x49, 0x46, 0x46],
      secondaryOffset: 8,
      secondaryBytes: [0x57, 0x45, 0x42, 0x50],
    ),
  ];

  /// Case-insensitive regex matching PHP/script injection patterns.
  ///
  /// Used by `ContextualSignatureAnalyzer` for embedded payload scanning AFTER
  /// the magic-byte gate has been passed.
  static final RegExp pattern = RegExp(
    r'<\?php|eval\s*\(|base64_decode\s*\(|passthru\s*\(|system\s*\(|shell_exec\s*\(',
    caseSensitive: false,
  );

  /// Returns the matching [MagicSignature] for [bytes], or `null` if no
  /// signature matches at its declared offset (and secondary offset, if any).
  ///
  /// Strict offset enforcement: the signature MUST appear at the exact
  /// declared offset — no scanning, no skipping null padding (Red Team Case F).
  /// WebP secondary offset is conjunctive: both checks must pass.
  static MagicSignature? matchSignature(List<int> bytes) {
    for (final sig in magicSignatures) {
      if (!_matchesAt(bytes, sig.offset, sig.bytes)) continue;
      final secOffset = sig.secondaryOffset;
      final secBytes = sig.secondaryBytes;
      if (secOffset != null && secBytes != null) {
        if (!_matchesAt(bytes, secOffset, secBytes)) continue;
      }
      return sig;
    }
    return null;
  }

  static bool _matchesAt(List<int> bytes, int offset, List<int> pattern) {
    final end = offset + pattern.length;
    if (bytes.length < end) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[offset + i] != pattern[i]) return false;
    }
    return true;
  }
}
