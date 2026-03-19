import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'domain_exception.dart';
import 'ingestion_integrity_flag.dart';

/// The normalized, provider-agnostic telemetry event — the veraprobEvent.
///
/// A [CanonicalFact] is produced by an Edge Function Adapter (Sascar, Omnitracs)
/// after it has:
///   1. Sealed the raw payload with SHA-256 in `raw_telemetry_payloads`.
///   2. Validated and mapped provider-specific fields to this canonical shape.
///   3. Classified the event with an [IngestionIntegrityFlag].
///
/// The Core Domain (EvaluationEngine) consumes only [CanonicalFact] — it never
/// sees raw provider JSON. This enforces INV-14 (Adapter Isolation).
///
/// **Key temporal fields (INV-16):**
/// - [receivedAtUtc]: server-side timestamp set by the Edge Function.
///   Immutable and authoritative for forensic timeline reconstruction.
/// - [gpsTimestamp]: device-reported timestamp. Variable trust — may be late,
///   in the future, or absent on some hardware.
///
/// **Invariants enforced:**
/// - INV-1: append-only — no mutation after creation.
/// - INV-3: both timestamps must be UTC.
/// - INV-4: zero Flutter/Supabase dependencies.
/// - INV-6: [organizationId] present on every record.
/// - INV-14: raw provider payload never exposed to the domain.
/// - INV-16: [receivedAtUtc] and [gpsTimestamp] are always distinct fields.
class CanonicalFact extends Equatable {
  // ── Identity ──────────────────────────────────────────────────────────────
  final String id;
  final String organizationId;

  // ── Provenance ────────────────────────────────────────────────────────────
  /// Foreign key to `raw_telemetry_payloads.id` — the sealed blob this fact
  /// was derived from. Required for forensic chain of custody.
  final String rawPayloadId;

  /// Identifier of the registered asset (vehicle) in the tenant's fleet.
  /// Null if the device is not yet mapped to an asset in this organization.
  final String? assetId;

  /// Hardware device identifier as reported by the provider (e.g., serial number).
  final String deviceId;

  /// Adapter that produced this fact (e.g., 'SASCAR_V1', 'OMNITRACS_V2').
  final String sourceAdapter;

  // ── Temporal (INV-16) ─────────────────────────────────────────────────────
  /// UTC timestamp when the raw payload arrived at the Edge Function.
  /// Set server-side; immutable forensic anchor.
  final DateTime receivedAtUtc;

  /// UTC timestamp reported by the GPS device.
  /// May differ from [receivedAtUtc] due to network latency or clock drift.
  final DateTime gpsTimestamp;

  // ── Geospatial ────────────────────────────────────────────────────────────
  final double lat;
  final double lng;

  /// Speed in centimetres per second. Null if unavailable from provider.
  /// INV-2: integer cm/s — no floating-point precision loss.
  final int? speedCms;

  /// Heading in degrees 0–359. Null if unavailable.
  final int? headingDegrees;

  /// GPS accuracy radius in metres. Null if not reported.
  final double? accuracyMeters;

  // ── Quality ───────────────────────────────────────────────────────────────
  /// Classification assigned by the Adapter at normalization time.
  /// [IngestionIntegrityFlag.ok] = safe for Engine evaluation.
  final IngestionIntegrityFlag integrityFlag;

  // ── Private constructor ───────────────────────────────────────────────────
  const CanonicalFact._({
    required this.id,
    required this.organizationId,
    required this.rawPayloadId,
    this.assetId,
    required this.deviceId,
    required this.sourceAdapter,
    required this.receivedAtUtc,
    required this.gpsTimestamp,
    required this.lat,
    required this.lng,
    this.speedCms,
    this.headingDegrees,
    this.accuracyMeters,
    required this.integrityFlag,
  });

  /// Creates a new [CanonicalFact], applying all domain invariants.
  ///
  /// The [integrityFlag] should be pre-computed by the caller (the Adapter)
  /// based on chaos tolerance rules (late arrival threshold, kinematics, etc.).
  ///
  /// Throws [DomainException] if any invariant is violated.
  factory CanonicalFact.create({
    required String organizationId,
    required String rawPayloadId,
    String? assetId,
    required String deviceId,
    required String sourceAdapter,
    required DateTime receivedAtUtc,
    required DateTime gpsTimestamp,
    required double lat,
    required double lng,
    int? speedCms,
    int? headingDegrees,
    double? accuracyMeters,
    required IngestionIntegrityFlag integrityFlag,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (rawPayloadId.isEmpty) {
      throw const DomainException('rawPayloadId must not be empty');
    }
    if (deviceId.isEmpty) {
      throw const DomainException('deviceId must not be empty');
    }
    if (sourceAdapter.isEmpty) {
      throw const DomainException('sourceAdapter must not be empty');
    }
    if (!receivedAtUtc.isUtc) {
      throw const DomainException(
        'receivedAtUtc must be UTC (INV-3). Call .toUtc() before passing.',
      );
    }
    if (!gpsTimestamp.isUtc) {
      throw const DomainException(
        'gpsTimestamp must be UTC (INV-3). Call .toUtc() before passing.',
      );
    }
    if (lat < -90 || lat > 90) {
      throw const DomainException('lat must be between -90 and 90');
    }
    if (lng < -180 || lng > 180) {
      throw const DomainException('lng must be between -180 and 180');
    }
    if (speedCms != null && speedCms < 0) {
      throw const DomainException('speedCms must be >= 0 when provided');
    }
    if (headingDegrees != null &&
        (headingDegrees < 0 || headingDegrees > 359)) {
      throw const DomainException(
        'headingDegrees must be between 0 and 359 when provided',
      );
    }
    if (accuracyMeters != null && accuracyMeters < 0) {
      throw const DomainException('accuracyMeters must be >= 0 when provided');
    }

    return CanonicalFact._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      rawPayloadId: rawPayloadId,
      assetId: assetId,
      deviceId: deviceId,
      sourceAdapter: sourceAdapter,
      receivedAtUtc: receivedAtUtc,
      gpsTimestamp: gpsTimestamp,
      lat: lat,
      lng: lng,
      speedCms: speedCms,
      headingDegrees: headingDegrees,
      accuracyMeters: accuracyMeters,
      integrityFlag: integrityFlag,
    );
  }

  /// Reconstitutes a [CanonicalFact] from persistence.
  /// Does NOT validate invariants — trusts that stored data was valid on insert.
  factory CanonicalFact.reconstitute({
    required String id,
    required String organizationId,
    required String rawPayloadId,
    String? assetId,
    required String deviceId,
    required String sourceAdapter,
    required DateTime receivedAtUtc,
    required DateTime gpsTimestamp,
    required double lat,
    required double lng,
    int? speedCms,
    int? headingDegrees,
    double? accuracyMeters,
    required IngestionIntegrityFlag integrityFlag,
  }) {
    return CanonicalFact._(
      id: id,
      organizationId: organizationId,
      rawPayloadId: rawPayloadId,
      assetId: assetId,
      deviceId: deviceId,
      sourceAdapter: sourceAdapter,
      receivedAtUtc: receivedAtUtc,
      gpsTimestamp: gpsTimestamp,
      lat: lat,
      lng: lng,
      speedCms: speedCms,
      headingDegrees: headingDegrees,
      accuracyMeters: accuracyMeters,
      integrityFlag: integrityFlag,
    );
  }

  /// Whether this fact is safe for [EvaluationEngine] consumption.
  bool get isEligibleForEvaluation =>
      integrityFlag == IngestionIntegrityFlag.ok ||
      integrityFlag == IngestionIntegrityFlag.lateArrival;

  /// Telemetry latency: difference between server receipt and device timestamp.
  /// Positive = late arrival. Negative = future timestamp (clock drift).
  Duration get telemetryLatency => receivedAtUtc.difference(gpsTimestamp);

  @override
  List<Object?> get props => [id];
}
