import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'domain_exception.dart';

/// Domain entity representing an individual telemetry information point captured
/// during a contractual service execution.
///
/// Evidence forms a cryptographic hash chain — each record commits to the
/// previous one, making any tampering detectable. This implements the
/// Evidence Locker invariant (Bloco 6).
///
/// **Chain integrity:**
/// - [contentHash]  = SHA-256 of the canonical payload fields.
/// - [chainHash]    = SHA-256([contentHash] + [previousEvidenceHash]).
/// - First record in a SET chain uses [kGenesisHash] as [previousEvidenceHash].
///
/// **Invariants enforced:**
/// - INV-1: append-only — no mutation after creation.
/// - INV-2: speed stored as integer cm/s to avoid float precision.
/// - INV-3: [capturedAtUtc] is always UTC.
/// - INV-4: zero Flutter/Supabase dependencies.
/// - INV-6: [organizationId] present on every record.
class TelemetryEvidence extends Equatable {
  /// Sentinel value used as [previousEvidenceHash] for the first record
  /// in a SET's evidence chain.
  static const String kGenesisHash = 'GENESIS';

  // ── Identity ──────────────────────────────────────────────────────────────
  final String id;
  final String organizationId;

  // ── Chain linkage ─────────────────────────────────────────────────────────
  /// SHA-256 of the canonical payload. Deterministic for the same input.
  final String contentHash;

  /// [chainHash] of the preceding evidence record, or [kGenesisHash] if first.
  final String previousEvidenceHash;

  /// SHA-256([contentHash] + [previousEvidenceHash]).
  /// Computed at creation time — never stored from external input.
  final String chainHash;

  // ── Service linkage ───────────────────────────────────────────────────────
  /// The SET this evidence belongs to.
  final String setId;
  final String vehicleId;

  // ── Temporal — INV-3: UTC always ─────────────────────────────────────────
  final DateTime capturedAtUtc;

  // ── Geospatial payload ───────────────────────────────────────────────────
  final double rawLatitude; // Physical Metric - Double Required
  final double rawLongitude; // Physical Metric - Double Required

  /// Speed in centimetres per second (integer). Null if unavailable.
  /// INV-2: stored as integer, not float, to avoid floating-point imprecision.
  final int? rawSpeedCms;

  // ── Source metadata ───────────────────────────────────────────────────────
  /// Describes how this evidence was captured (e.g., "GPS_PING", "MANUAL_UPLOAD").
  final String sourceType;

  const TelemetryEvidence._({
    required this.id,
    required this.organizationId,
    required this.setId,
    required this.vehicleId,
    required this.capturedAtUtc,
    required this.rawLatitude,
    required this.rawLongitude,
    required this.rawSpeedCms,
    required this.sourceType,
    required this.contentHash,
    required this.previousEvidenceHash,
    required this.chainHash,
  });

  /// Creates a new [TelemetryEvidence] record, computing [contentHash] and
  /// [chainHash] from the provided payload.
  ///
  /// [previousEvidenceHash]: pass [kGenesisHash] for the first record in a
  /// SET's chain, or the [chainHash] of the preceding record.
  ///
  /// Throws [DomainException] if any field invariant is violated.
  factory TelemetryEvidence.create({
    required String organizationId,
    required String setId,
    required String vehicleId,
    required DateTime capturedAtUtc,
    required double rawLatitude, // Physical Metric - Double Required
    required double rawLongitude, // Physical Metric - Double Required
    int? rawSpeedCms,
    required String sourceType,
    required String previousEvidenceHash,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (setId.isEmpty) {
      throw const DomainException('setId must not be empty');
    }
    if (vehicleId.isEmpty) {
      throw const DomainException('vehicleId must not be empty');
    }
    if (!capturedAtUtc.isUtc) {
      throw const DomainException(
        'capturedAtUtc must be UTC (INV-3). Call .toUtc() before passing.',
      );
    }
    if (rawLatitude < -90 || rawLatitude > 90) {
      throw const DomainException('rawLatitude must be between -90 and 90');
    }
    if (rawLongitude < -180 || rawLongitude > 180) {
      throw const DomainException('rawLongitude must be between -180 and 180');
    }
    if (rawSpeedCms != null && rawSpeedCms < 0) {
      throw const DomainException('rawSpeedCms must be >= 0 when provided');
    }
    if (sourceType.isEmpty) {
      throw const DomainException('sourceType must not be empty');
    }
    if (previousEvidenceHash.isEmpty) {
      throw const DomainException('previousEvidenceHash must not be empty');
    }

    final id = const Uuid().v4();
    final contentHash = _computeContentHash(
      id: id,
      organizationId: organizationId,
      setId: setId,
      vehicleId: vehicleId,
      capturedAtUtc: capturedAtUtc,
      rawLatitude: rawLatitude,
      rawLongitude: rawLongitude,
      rawSpeedCms: rawSpeedCms,
      sourceType: sourceType,
    );
    final chainHash = _computeChainHash(contentHash, previousEvidenceHash);

    return TelemetryEvidence._(
      id: id,
      organizationId: organizationId,
      setId: setId,
      vehicleId: vehicleId,
      capturedAtUtc: capturedAtUtc,
      rawLatitude: rawLatitude,
      rawLongitude: rawLongitude,
      rawSpeedCms: rawSpeedCms,
      sourceType: sourceType,
      contentHash: contentHash,
      previousEvidenceHash: previousEvidenceHash,
      chainHash: chainHash,
    );
  }

  /// Reconstitutes from persistence. Does NOT recompute hashes — trusts stored values.
  /// Use [verifyIntegrity] after reconstitution if tamper detection is needed.
  factory TelemetryEvidence.reconstitute({
    required String id,
    required String organizationId,
    required String setId,
    required String vehicleId,
    required DateTime capturedAtUtc,
    required double rawLatitude, // Physical Metric - Double Required
    required double rawLongitude, // Physical Metric - Double Required
    int? rawSpeedCms,
    required String sourceType,
    required String contentHash,
    required String previousEvidenceHash,
    required String chainHash,
  }) {
    return TelemetryEvidence._(
      id: id,
      organizationId: organizationId,
      setId: setId,
      vehicleId: vehicleId,
      capturedAtUtc: capturedAtUtc,
      rawLatitude: rawLatitude,
      rawLongitude: rawLongitude,
      rawSpeedCms: rawSpeedCms,
      sourceType: sourceType,
      contentHash: contentHash,
      previousEvidenceHash: previousEvidenceHash,
      chainHash: chainHash,
    );
  }

  /// Recomputes [contentHash] and [chainHash] from stored fields and compares
  /// to the stored values. Returns `false` if any field was mutated.
  bool verifyIntegrity() {
    final recomputedContent = _computeContentHash(
      id: id,
      organizationId: organizationId,
      setId: setId,
      vehicleId: vehicleId,
      capturedAtUtc: capturedAtUtc,
      rawLatitude: rawLatitude,
      rawLongitude: rawLongitude,
      rawSpeedCms: rawSpeedCms,
      sourceType: sourceType,
    );
    if (recomputedContent != contentHash) return false;

    final recomputedChain = _computeChainHash(
      contentHash,
      previousEvidenceHash,
    );
    return recomputedChain == chainHash;
  }

  // ── Private hash helpers ──────────────────────────────────────────────────

  /// Canonical payload for content hashing. Field order is fixed — do not change.
  static String _computeContentHash({
    required String id,
    required String organizationId,
    required String setId,
    required String vehicleId,
    required DateTime capturedAtUtc,
    required double rawLatitude, // Physical Metric - Double Required
    required double rawLongitude, // Physical Metric - Double Required
    required int? rawSpeedCms,
    required String sourceType,
  }) {
    final canonical = {
      'id': id,
      'organization_id': organizationId,
      'set_id': setId,
      'vehicle_id': vehicleId,
      'captured_at_utc': capturedAtUtc.toIso8601String(),
      'raw_latitude': rawLatitude,
      'raw_longitude': rawLongitude,
      'raw_speed_cms': rawSpeedCms,
      'source_type': sourceType,
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  static String _computeChainHash(
    String contentHash,
    String previousEvidenceHash,
  ) {
    return sha256
        .convert(utf8.encode(contentHash + previousEvidenceHash))
        .toString();
  }

  @override
  List<Object?> get props => [id];
}
