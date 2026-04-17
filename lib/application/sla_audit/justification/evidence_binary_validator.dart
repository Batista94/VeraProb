/// Forensic Audit Signature: CX-05-v2.1
/// Remediation: Red Team ID 3 (Binary Inspection Gap)
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb Senior Engineer
///
/// Validates file types by reading binary signatures (Magic Bytes), not extensions.
/// Prevents malicious files (executables, SVG with scripts) from being uploaded
/// as evidence by checking the actual file content, not just the filename.
///
/// **Defense-in-Depth Layer 2:** Binary inspection occurs AFTER XSS sanitization
/// and BEFORE SHA-256 hash verification.
///
/// **Forensic Guarantee:** All evidence files stored in Supabase Storage are
/// guaranteed to match the MIME whitelist (JPEG, PNG, PDF, HEIC, WebP).
library;

import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

/// Validates file types by reading Magic Bytes (Red Team ID 3).
///
/// Reads the first 512 bytes of each file and matches against known signatures.
/// Rejects files that don't match the MIME whitelist, even if the extension is correct.
class EvidenceBinaryValidator {
  final EvidenceStorageReader _reader;

  /// MIME type whitelist: JPEG, PNG, PDF, HEIC/HEIF, WebP.
  /// Extended from original requirement to support modern device formats.
  static const List<String> _allowedMimeTypes = [
    'image/jpeg',
    'image/png',
    'application/pdf',
    'image/heic',
    'image/heif',
    'image/webp',
  ];

  EvidenceBinaryValidator(this._reader);

  /// Validates all [urls] against the MIME whitelist and scans for script payloads.
  ///
  /// [fileSizes] allows providing pre-fetched file sizes to enable Jump Sampling
  /// (Fix 4). If null, a linear scan fallback is used for safety.
  ///
  /// Throws [DomainException] if any file fails MIME validation.
  /// Throws [ForensicViolationException] if any file contains a script payload
  /// detected via Jump Sampling or linear scan.
  /// Returns silently if all files pass both checks.
  Future<void> validateEvidence(
    List<String> urls, {
    List<int?>? fileSizes,
  }) async {
    for (var i = 0; i < urls.length; i++) {
      final mimeType = await detectMimeType(urls[i]);
      if (mimeType == null || !_allowedMimeTypes.contains(mimeType)) {
        throw DomainException(
          'Invalid file type detected at evidence index $i: '
          '${mimeType ?? 'unknown'}. Allowed types: ${_allowedMimeTypes.join(', ')}',
        );
      }
      // Fix 4: scan beyond Magic Bytes header for embedded script payloads
      // using Jump Sampling if file size is known and > 1MB.
      final size = (fileSizes != null && i < fileSizes.length)
          ? fileSizes[i]
          : null;
      await _scanForScriptPayloads(urls[i], fileSize: size);
    }
  }

  /// Detects MIME type by reading Magic Bytes from [url].
  ///
  /// Returns null if the file signature doesn't match any known type.
  ///
  /// **Magic Byte Signatures:**
  /// - JPEG: `FF D8 FF` at offset 0
  /// - PNG: `89 50 4E 47 0D 0A 1A 0A` at offset 0
  /// - PDF: `25 50 44 46` (`%PDF`) at offset 0
  /// - HEIC: `66 74 79 70 68 65 69 63` at offset 4 (preceded by box length)
  /// - WebP: `52 49 46 46` at offset 0, then `57 45 42 50` at offset 8
  Future<String?> detectMimeType(String url) async {
    try {
      final bytes = await _readFirst512Bytes(url);

      // JPEG: FF D8 FF
      if (bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF) {
        return 'image/jpeg';
      }

      // PNG: 89 50 4E 47 0D 0A 1A 0A
      if (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A) {
        return 'image/png';
      }

      // PDF: 25 50 44 46 (%PDF)
      if (bytes.length >= 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46) {
        return 'application/pdf';
      }

      // HEIC: 66 74 79 70 68 65 69 63 at offset 4
      // Preceded by box length (typically 00 00 00 18 or 00 00 00 20)
      if (bytes.length >= 12 &&
          bytes[4] == 0x66 && // f
          bytes[5] == 0x74 && // t
          bytes[6] == 0x79 && // y
          bytes[7] == 0x70 && // p
          bytes[8] == 0x68 && // h
          bytes[9] == 0x65 && // e
          bytes[10] == 0x69 && // i
          bytes[11] == 0x63) {
        // c
        return 'image/heic';
      }

      // HEIF: Same structure as HEIC but with 'heif' instead of 'heic'
      if (bytes.length >= 12 &&
          bytes[4] == 0x66 && // f
          bytes[5] == 0x74 && // t
          bytes[6] == 0x79 && // y
          bytes[7] == 0x70 && // p
          bytes[8] == 0x68 && // h
          bytes[9] == 0x65 && // e
          bytes[10] == 0x69 && // i
          bytes[11] == 0x66) {
        // f
        return 'image/heif';
      }

      // WebP: 52 49 46 46 (RIFF) at offset 0, then 57 45 42 50 (WEBP) at offset 8
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 && // R
          bytes[1] == 0x49 && // I
          bytes[2] == 0x46 && // F
          bytes[3] == 0x46 && // F
          bytes[8] == 0x57 && // W
          bytes[9] == 0x45 && // E
          bytes[10] == 0x42 && // B
          bytes[11] == 0x50) {
        // P
        return 'image/webp';
      }

      return null; // Unknown file type
    } catch (_) {
      return null; // Read error = treat as unknown type
    }
  }

  /// Reads the first 512 bytes from [url] using the storage reader.
  Future<List<int>> _readFirst512Bytes(String url) async {
    final buffer = <int>[];
    await for (final chunk in _reader.streamBytes(url: url)) {
      buffer.addAll(chunk);
      if (buffer.length >= 512) break;
    }
    return buffer.take(512).toList();
  }

  /// Scans for script signatures using either Jump Sampling or Linear Scan (Fix 4).
  ///
  /// **Jump Sampling (Large Files > 1MB):**
  /// Probes three 1KB windows (Start, Middle, End) in parallel via [readRange].
  ///
  /// **Linear Scan (Small Files or Unknown Size):**
  /// Reads up to 1MB from the start of the file.
  ///
  /// **OOM Prevention:** Never buffers more than ~3KB total for Jump Sampling
  /// or 1MB for Linear Scan.
  Future<void> _scanForScriptPayloads(String url, {int? fileSize}) async {
    final List<({String name, int offset, List<int> bytes})> probes;

    if (fileSize != null && fileSize > 1024 * 1024) {
      // Jump Sampling: Parallel probes (CX-05-v2.2)
      final results = await Future.wait([
        _reader.readRange(url: url, start: 0, length: 1024),
        _reader.readRange(url: url, start: fileSize ~/ 2, length: 1024),
        _reader.readRange(url: url, start: fileSize - 1024, length: 1024),
      ]);

      probes = [
        (name: 'Start', offset: 0, bytes: results[0]),
        (name: 'Middle', offset: fileSize ~/ 2, bytes: results[1]),
        (name: 'Tail', offset: fileSize - 1024, bytes: results[2]),
      ];
    } else {
      // Fallback: Linear Scan (Limited to 1MB)
      final bytes = <int>[];
      var bytesRead = 0;
      await for (final chunk in _reader.streamBytes(url: url)) {
        bytes.addAll(chunk);
        bytesRead += chunk.length;
        if (bytesRead >= 1024 * 1024) break;
      }
      probes = [
        (name: 'Linear', offset: 0, bytes: bytes.take(1024 * 1024).toList()),
      ];
    }

    const signatures = ['<?php', '<script', 'eval(', 'base64_decode'];

    for (final probe in probes) {
      final text = String.fromCharCodes(probe.bytes).toLowerCase();
      for (final sig in signatures) {
        if (text.contains(sig)) {
          throw ForensicViolationException(
            message:
                '[Probe: ${probe.name}] Signature "$sig" found '
                'at offset ${probe.offset}. Forensic integrity violation — CX05-Fix-4.',
            evidenceUrl: url,
          );
        }
      }
    }
  }
}
