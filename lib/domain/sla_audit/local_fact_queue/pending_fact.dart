import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../canonical_fact.dart';
import '../ingestion_integrity_flag.dart';
import 'sync_status.dart';

/// An immutable snapshot of a [CanonicalFact] buffered in the local
/// Edge Ledger (SQLite/WasmDatabase) for offline Chain-of-Custody continuity.
///
/// **Hash integrity (INV-8):**
/// [contentHash] is a SHA-256 digest of [factPayloadJson], computed at
/// creation time and stored verbatim.  [verifyIntegrity] recomputes the
/// digest and compares it, detecting any in-place SQLite mutation.
///
/// **Idempotency (INV-11):**
/// [factId] mirrors [CanonicalFact.id].  The repository enforces a UNIQUE
/// constraint on [factId], so re-enqueueing the same fact is a no-op.
///
/// **UTC (INV-9):**
/// [receivedAtUtc] and [queuedAtUtc] are always UTC.
///
/// **Pure Dart (INV-18):** zero Flutter / Supabase dependencies.
class PendingFact extends Equatable {
  // ── Identity ──────────────────────────────────────────────────────────────

  /// Mirrors [CanonicalFact.id] — the global idempotency key.
  final String factId;

  final String organizationId;

  // ── Integrity (INV-8) ─────────────────────────────────────────────────────

  /// SHA-256([factPayloadJson]) computed at enqueue time.
  /// Never mutated after creation.
  final String contentHash;

  /// Deterministic JSON serialisation of the source [CanonicalFact].
  /// The hash above is computed over this string.
  final String factPayloadJson;

  // ── Temporal (INV-9: UTC) ─────────────────────────────────────────────────

  /// When the OCC first received this fact from Supabase Realtime.
  final DateTime receivedAtUtc;

  /// When the fact was written to the local SQLite queue.
  final DateTime queuedAtUtc;

  // ── Sync state ────────────────────────────────────────────────────────────

  final SyncStatus syncStatus;

  /// Monotonically increasing counter assigned by the repository.
  /// Used for sequence-gap detection during handshake.
  final int localSequence;

  /// Number of failed delivery attempts (for back-off logic).
  final int retryCount;

  /// Last error message from a failed submission attempt.
  final String? errorMessage;

  // ── Private constructor ───────────────────────────────────────────────────

  const PendingFact._({
    required this.factId,
    required this.organizationId,
    required this.contentHash,
    required this.factPayloadJson,
    required this.receivedAtUtc,
    required this.queuedAtUtc,
    required this.syncStatus,
    required this.localSequence,
    required this.retryCount,
    this.errorMessage,
  });

  // ── Factories ─────────────────────────────────────────────────────────────

  /// Creates a [PendingFact] from a freshly received [CanonicalFact].
  ///
  /// Serialises [fact] to a canonical JSON string, computes the SHA-256
  /// [contentHash], and stamps [queuedAtUtc].
  ///
  /// [localSequence] must be provided by the repository (monotonic counter).
  /// [nowUtc] can be injected in tests to produce deterministic timestamps.
  factory PendingFact.fromIncomingFact(
    CanonicalFact fact, {
    required int localSequence,
    DateTime? nowUtc,
  }) {
    final payloadMap = _canonicalJsonMap(fact);
    final payloadJson = jsonEncode(payloadMap);
    final hash = sha256.convert(utf8.encode(payloadJson)).toString();
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();

    return PendingFact._(
      factId: fact.id,
      organizationId: fact.organizationId,
      contentHash: hash,
      factPayloadJson: payloadJson,
      receivedAtUtc: fact.receivedAtUtc,
      queuedAtUtc: now,
      syncStatus: SyncStatus.pending,
      localSequence: localSequence,
      retryCount: 0,
    );
  }

  /// Reconstitutes a [PendingFact] from a SQLite row.
  /// Skips hash recomputation — call [verifyIntegrity] separately when needed.
  factory PendingFact.reconstitute({
    required String factId,
    required String organizationId,
    required String contentHash,
    required String factPayloadJson,
    required DateTime receivedAtUtc,
    required DateTime queuedAtUtc,
    required SyncStatus syncStatus,
    required int localSequence,
    required int retryCount,
    String? errorMessage,
  }) {
    return PendingFact._(
      factId: factId,
      organizationId: organizationId,
      contentHash: contentHash,
      factPayloadJson: factPayloadJson,
      receivedAtUtc: receivedAtUtc,
      queuedAtUtc: queuedAtUtc,
      syncStatus: syncStatus,
      localSequence: localSequence,
      retryCount: retryCount,
      errorMessage: errorMessage,
    );
  }

  // ── Integrity verification (INV-8) ────────────────────────────────────────

  /// Returns `true` when SHA-256([factPayloadJson]) matches [contentHash].
  ///
  /// A `false` result means the locally stored payload has been mutated —
  /// the fact must be discarded and requested via gap-fill handshake.
  bool verifyIntegrity() {
    final recomputed = sha256.convert(utf8.encode(factPayloadJson)).toString();
    return recomputed == contentHash;
  }

  // ── Derived state helpers ─────────────────────────────────────────────────

  bool get isPending => syncStatus == SyncStatus.pending;
  bool get isFailed => syncStatus == SyncStatus.failed;
  bool get isAcknowledged => syncStatus == SyncStatus.acknowledged;

  // ── Equatable ─────────────────────────────────────────────────────────────

  @override
  List<Object?> get props => [factId];

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Canonical JSON map for a [CanonicalFact] — field order is deterministic
  /// so the SHA-256 digest is stable across serialisation/deserialisation.
  static Map<String, dynamic> _canonicalJsonMap(CanonicalFact fact) {
    return {
      'id': fact.id,
      'organizationId': fact.organizationId,
      'rawPayloadId': fact.rawPayloadId,
      'assetId': fact.assetId,
      'deviceId': fact.deviceId,
      'sourceAdapter': fact.sourceAdapter,
      'receivedAtUtc': fact.receivedAtUtc.toIso8601String(),
      'gpsTimestamp': fact.gpsTimestamp.toIso8601String(),
      'lat': fact.lat,
      'lng': fact.lng,
      'speedCms': fact.speedCms,
      'headingDegrees': fact.headingDegrees,
      'accuracyMeters': fact.accuracyMeters,
      'integrityFlag': fact.integrityFlag.name,
    };
  }

  /// Reconstructs a [CanonicalFact] from [factPayloadJson].
  /// Used by consumers that need the original domain entity.
  CanonicalFact toCanonicalFact() {
    final map = jsonDecode(factPayloadJson) as Map<String, dynamic>;
    return CanonicalFact.reconstitute(
      id: map['id'] as String,
      organizationId: map['organizationId'] as String,
      rawPayloadId: map['rawPayloadId'] as String,
      assetId: map['assetId'] as String?,
      deviceId: map['deviceId'] as String,
      sourceAdapter: map['sourceAdapter'] as String,
      receivedAtUtc: DateTime.parse(map['receivedAtUtc'] as String).toUtc(),
      gpsTimestamp: DateTime.parse(map['gpsTimestamp'] as String).toUtc(),
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      speedCms: (map['speedCms'] as num?)?.toInt(),
      headingDegrees: (map['headingDegrees'] as num?)?.toInt(),
      accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
      integrityFlag: IngestionIntegrityFlag.values.byName(
        map['integrityFlag'] as String,
      ),
    );
  }

  /// Generates a new UUID — convenience helper used by tests.
  static String newId() => const Uuid().v4();
}
