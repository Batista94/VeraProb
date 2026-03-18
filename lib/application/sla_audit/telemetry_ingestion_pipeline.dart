import 'dart:math' show asin, cos, sqrt;

import '../../domain/entities/vehicle_operational_state.dart';
import '../../domain/enums/connectivity_state.dart';
import '../../domain/enums/motion_state.dart';
import '../../domain/sla_audit/asset_status.dart';
import '../../domain/sla_audit/asset_status_repository.dart';
import '../../domain/sla_audit/canonical_fact.dart';
import '../../domain/sla_audit/ingestion_integrity_flag.dart';
import 'contractual_evaluation_engine.dart';

/// Result of a [TelemetryIngestionPipeline.process] call.
///
/// Provides observability into what happened during the pipeline run —
/// how many facts were processed, skipped, and why.
class IngestionPipelineResult {
  /// Facts that reached the [ContractualEvaluationEngine].
  final int processed;

  /// Facts skipped because [CanonicalFact.isEligibleForEvaluation] == false.
  final int skippedByIntegrityFlag;

  /// Facts skipped by the sequential kinematic jump check (6.5.4).
  /// These had a valid stored flag but failed the in-pipeline Haversine check.
  final int skippedByKinematicJump;

  /// Facts skipped because the asset was in [AssetStatus.maintenance] or
  /// [AssetStatus.offDuty] at [gpsTimestamp] (6.5.3 / INV-13).
  final int skippedByAssetStatus;

  /// Facts with [IngestionIntegrityFlag.lateArrival] that were still processed.
  /// High counts indicate network/hardware latency issues worth investigating.
  final int lateArrivalCount;

  /// Asset IDs for which at least one late-arrival fact was processed.
  /// Used by downstream services to flag SETs for retroactive review (Phase 7.5.1).
  final List<String> lateArrivalAssetIds;

  const IngestionPipelineResult({
    required this.processed,
    required this.skippedByIntegrityFlag,
    required this.skippedByKinematicJump,
    required this.skippedByAssetStatus,
    required this.lateArrivalCount,
    required this.lateArrivalAssetIds,
  });

  int get totalReceived =>
      processed +
      skippedByIntegrityFlag +
      skippedByKinematicJump +
      skippedByAssetStatus;
}

/// Application service that bridges [CanonicalFact] records to the
/// [ContractualEvaluationEngine].
///
/// Implements the chaos-tolerance pipeline for Phase 6.5:
///
/// **6.5.2 — Chronological Chaos Tolerance:**
/// - Sorts incoming facts by [gpsTimestamp] ascending (INV-12).
/// - Passes [gpsTimestamp] as the `nowUtc` clock to the engine, ensuring
///   evaluation is deterministic regardless of network arrival order.
///
/// **6.5.3 — Asset State Machine:**
/// - Checks [AssetStatusRepository] before evaluation.
/// - Facts for assets in [AssetStatus.maintenance] or [AssetStatus.offDuty]
///   are skipped — no false-positive SLA violations (INV-13).
///
/// **6.5.4 — Kinematic Noise Filter:**
/// - Applies a sequential Haversine jump check between consecutive facts
///   for the same device (stateful, in-memory per pipeline run).
/// - Complements the Edge Function's single-point checks with a sequence-aware
///   filter that catches GPS jitter causing false geofence exits.
class TelemetryIngestionPipeline {
  final ContractualEvaluationEngine _engine;
  final AssetStatusRepository? _assetStatusRepo;

  /// Maximum implied speed (km/h) allowed between consecutive facts.
  /// Facts that imply a higher speed are discarded as kinematic anomalies.
  final double maxImpliedSpeedKmh;

  TelemetryIngestionPipeline({
    required ContractualEvaluationEngine engine,
    AssetStatusRepository? assetStatusRepo,
    this.maxImpliedSpeedKmh = 200.0,
  }) : _engine = engine,
       _assetStatusRepo = assetStatusRepo;

  /// Processes a batch of [CanonicalFact] records for the given [organizationId].
  ///
  /// The caller is responsible for fetching the facts from the repository
  /// (typically: all unprocessed facts since last pipeline run, per asset).
  ///
  /// Facts need NOT be pre-sorted — the pipeline sorts them chronologically.
  Future<IngestionPipelineResult> process(
    List<CanonicalFact> facts, {
    required String organizationId,
  }) async {
    // ── 6.5.2: Sort by gpsTimestamp ASC (INV-12: Chronological Determinism) ──
    final sorted = List<CanonicalFact>.from(facts)
      ..sort((a, b) => a.gpsTimestamp.compareTo(b.gpsTimestamp));

    int skippedByIntegrityFlag = 0;
    int skippedByKinematicJump = 0;
    int skippedByAssetStatus = 0;
    int processed = 0;
    int lateArrivalCount = 0;
    final Set<String> lateArrivalAssetIds = {};

    // ── 6.5.4: Per-device state for sequential kinematic check ───────────────
    final Map<String, CanonicalFact> _lastKnownFact = {};

    // ── Asset status cache (avoid repeated DB queries per fact) ──────────────
    final Map<String, AssetStatus> _statusCache = {};

    for (final fact in sorted) {
      // ── Step 1: Integrity flag filter (stored by Edge Function) ─────────────
      if (!fact.isEligibleForEvaluation) {
        skippedByIntegrityFlag++;
        continue;
      }

      // ── Step 2: Sequential kinematic jump check (6.5.4) ─────────────────────
      final deviceKey = '${fact.organizationId}|${fact.deviceId}';
      final lastFact = _lastKnownFact[deviceKey];

      if (lastFact != null) {
        final distanceM = _haversineMeters(
          lastFact.lat,
          lastFact.lng,
          fact.lat,
          fact.lng,
        );
        final timeDiffSeconds = fact.gpsTimestamp
            .difference(lastFact.gpsTimestamp)
            .inSeconds
            .abs();

        if (timeDiffSeconds > 0) {
          final impliedKmh = (distanceM / timeDiffSeconds) * 3.6;
          if (impliedKmh > maxImpliedSpeedKmh) {
            skippedByKinematicJump++;
            // Do NOT update _lastKnownFact — the previous valid point stands.
            continue;
          }
        } else if (distanceM > 5.0) {
          // Same timestamp but moved > 5m: hardware glitch
          skippedByKinematicJump++;
          continue;
        }
      }

      _lastKnownFact[deviceKey] = fact;

      // ── Step 3: Asset status check (6.5.3 / INV-13) ─────────────────────────
      if (_assetStatusRepo != null && fact.assetId != null) {
        final assetId = fact.assetId!;
        final cacheKey = '${organizationId}|$assetId';
        _statusCache[cacheKey] ??= await _assetStatusRepo.getCurrentStatus(
          assetId: assetId,
          organizationId: organizationId,
        );

        final status = _statusCache[cacheKey]!;
        if (status == AssetStatus.maintenance ||
            status == AssetStatus.offDuty) {
          skippedByAssetStatus++;
          continue;
        }
      }

      // ── Step 4: Convert to VehicleOperationalState ───────────────────────────
      final vehicleState = _factToVehicleState(fact);

      // ── Step 5: Feed engine with gpsTimestamp as the clock (INV-12) ──────────
      await _engine.processVehicleState(
        vehicleState,
        nowUtc: fact.gpsTimestamp,
        organizationId: organizationId,
      );

      processed++;

      if (fact.integrityFlag == IngestionIntegrityFlag.lateArrival) {
        lateArrivalCount++;
        if (fact.assetId != null) lateArrivalAssetIds.add(fact.assetId!);
      }
    }

    return IngestionPipelineResult(
      processed: processed,
      skippedByIntegrityFlag: skippedByIntegrityFlag,
      skippedByKinematicJump: skippedByKinematicJump,
      skippedByAssetStatus: skippedByAssetStatus,
      lateArrivalCount: lateArrivalCount,
      lateArrivalAssetIds: lateArrivalAssetIds.toList(),
    );
  }

  // ── Private: CanonicalFact → VehicleOperationalState bridge ─────────────────
  //
  // The engine only uses vehicleId, latitude, and longitude for geofence checks.
  // Other fields are filled with sensible defaults — the engine does not inspect them.
  VehicleOperationalState _factToVehicleState(CanonicalFact fact) {
    // Prefer registered assetId; fall back to deviceId for unregistered hardware.
    final vehicleId = fact.assetId ?? fact.deviceId;

    // cm/s → km/h
    final speedKmh = fact.speedCms != null ? fact.speedCms! * 0.036 : 0.0;

    return VehicleOperationalState(
      vehicleId: vehicleId,
      tripId:
          '', // No trip concept at ingestion level; engine does not use this
      latitude: fact.lat,
      longitude: fact.lng,
      heading: fact.headingDegrees?.toDouble(),
      smoothedSpeed: speedKmh,
      motionState: speedKmh > 1.0 ? MotionState.moving : MotionState.stopped,
      connectivityState: ConnectivityState.healthy,
      lastRawPingAt: fact.gpsTimestamp,
      stateChangedAt: fact.gpsTimestamp,
      confidence: 1.0,
      source: fact.sourceAdapter,
    );
  }

  // ── Haversine distance (metres) ──────────────────────────────────────────────
  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // pi / 180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000;
  }
}
