/// Forensic Audit Signature: CX-05-v2.2
/// Remediation: Red Team ID 3 (Binary Inspection Gap) — Fix 4 & 5
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb Senior Engineer
///
/// N=7 forensic file inspector: validates MIME type via Magic Bytes and scans
/// for embedded script payloads using Jump Sampling with random quintil offsets.
///
/// **Zero-Trust Metadata (INV-18):** file size is always fetched from the server
/// via authenticated HEAD — client-supplied sizes are never accepted.
///
/// **Probe Strategy:**
///   Fixed:   Start (offset 0) + End (offset fileSize−1024)
///   Dynamic: 5 probes, one per 20%-wide quintil, random within each band
///
/// **Concurrency:** up to 10 simultaneous range requests via inline [_Semaphore].
library;

import 'dart:async';
import 'dart:math';

import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

/// Validates evidence files with N=7 Jump Sampling and regex payload detection.
class EvidenceBinaryJumpSamplingValidator {
  final EvidenceStorageReader _reader;
  final Random _random;

  static const int _probeLength = 1024;
  static const int _concurrentProbeLimit = 10;
  static const int _largeSizeThreshold = 1024 * 1024; // 1 MB

  static const List<String> _allowedMimeTypes = [
    'image/jpeg',
    'image/png',
    'application/pdf',
    'image/heic',
    'image/heif',
    'image/webp',
  ];

  // Case-insensitive, whitespace-tolerant forensic payload pattern (CX-05-Fix-3).
  static final RegExp _payloadPattern = RegExp(
    r'<\?php|eval\s*\(|base64_decode\s*\(',
    caseSensitive: false,
  );

  EvidenceBinaryJumpSamplingValidator(this._reader, {Random? random})
    : _random = random ?? Random();

  /// Validates all [urls] against the MIME whitelist and scans for script payloads.
  ///
  /// File size is always retrieved via authenticated HEAD (Zero-Trust, INV-18).
  /// Throws [DomainException] on MIME mismatch.
  /// Throws [ForensicViolationException] on script payload detection.
  Future<void> validateEvidence(List<String> urls) async {
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final mimeType = await detectMimeType(url);
      if (mimeType == null || !_allowedMimeTypes.contains(mimeType)) {
        throw DomainException(
          'Invalid file type at evidence index $i: '
          '${mimeType ?? 'unknown'}. Allowed: ${_allowedMimeTypes.join(', ')}',
        );
      }
      await _scanForScriptPayloads(url);
    }
  }

  /// Detects MIME type by reading Magic Bytes from [url].
  Future<String?> detectMimeType(String url) async {
    try {
      final bytes = await _readFirst512Bytes(url);
      return _detectMimeFromBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _readFirst512Bytes(String url) async {
    final buffer = <int>[];
    await for (final chunk in _reader.streamBytes(url: url)) {
      buffer.addAll(chunk);
      if (buffer.length >= 512) break;
    }
    return buffer.take(512).toList();
  }

  String? _detectMimeFromBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

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

    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }

    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70 &&
        bytes[8] == 0x68 &&
        bytes[9] == 0x65 &&
        bytes[10] == 0x69 &&
        bytes[11] == 0x63) {
      return 'image/heic';
    }

    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70 &&
        bytes[8] == 0x68 &&
        bytes[9] == 0x65 &&
        bytes[10] == 0x69 &&
        bytes[11] == 0x66) {
      return 'image/heif';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    return null;
  }

  Future<void> _scanForScriptPayloads(String url) async {
    int fileSize;
    try {
      fileSize = await _reader.getContentLength(url: url);
    } catch (_) {
      await _linearScan(url);
      return;
    }

    if (fileSize <= _largeSizeThreshold) {
      await _linearScan(url);
      return;
    }

    final probes = _buildProbeOffsets(fileSize);
    final semaphore = _Semaphore(_concurrentProbeLimit);

    await Future.wait(
      probes.map(
        (probe) => _runProbe(url: url, probe: probe, semaphore: semaphore),
      ),
    );
  }

  List<({String name, int offset})> _buildProbeOffsets(int fileSize) {
    final quintilSize = fileSize ~/ 5;
    final probes = <({String name, int offset})>[(name: 'Start', offset: 0)];

    for (var i = 0; i < 5; i++) {
      final bandStart = i * quintilSize;
      final bandEnd = (i + 1) * quintilSize - _probeLength;
      final range = (bandEnd - bandStart).clamp(1, 1 << 30);
      final offset = bandStart + _random.nextInt(range);
      probes.add((name: 'Quintil${i + 1}', offset: offset));
    }

    probes.add((name: 'End', offset: fileSize - _probeLength));
    return probes;
  }

  Future<void> _runProbe({
    required String url,
    required ({String name, int offset}) probe,
    required _Semaphore semaphore,
  }) async {
    await semaphore.acquire();
    try {
      final bytes = await _reader.readRange(
        url: url,
        start: probe.offset,
        length: _probeLength,
      );
      _checkForPayload(
        bytes: bytes,
        url: url,
        probeName: probe.name,
        offset: probe.offset,
      );
    } finally {
      semaphore.release();
    }
  }

  Future<void> _linearScan(String url) async {
    final bytes = <int>[];
    await for (final chunk in _reader.streamBytes(url: url)) {
      bytes.addAll(chunk);
      if (bytes.length >= _largeSizeThreshold) break;
    }
    _checkForPayload(
      bytes: bytes.take(_largeSizeThreshold).toList(),
      url: url,
      probeName: 'Linear',
      offset: 0,
    );
  }

  void _checkForPayload({
    required List<int> bytes,
    required String url,
    required String probeName,
    required int offset,
  }) {
    final text = String.fromCharCodes(bytes);
    final match = _payloadPattern.firstMatch(text);
    if (match != null) {
      throw ForensicViolationException(
        message:
            '[Probe: $probeName] Signature "${match.group(0)}" found '
            'at offset $offset. Forensic integrity violation — CX05-Fix-4/5.',
        evidenceUrl: url,
      );
    }
  }
}

class _Semaphore {
  int _count;
  final _queue = <Completer<void>>[];

  _Semaphore(this._count);

  Future<void> acquire() async {
    if (_count > 0) {
      _count--;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
      return;
    }
    _count++;
  }
}
