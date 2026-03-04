import 'dart:async';
import 'dart:math';

import '../../application/sla_audit/sla_ledger_mapper.dart';
import '../../domain/entities/vehicle_operational_state.dart';
import '../../domain/sla_audit/contractual_execution_state.dart';
import '../../domain/sla_audit/execution_status.dart';
import '../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';

/// Application Service: Reactive evaluation engine for contractual
/// service execution obligations.
///
/// Connects vehicle telemetry to [ContractualExecutionState] aggregates
/// via geofence detection and dwell-time validation.
///
/// **Intentionally separate from [SituationEngine]** — this engine
/// evaluates contractual compliance, not operational anomalies.
///
/// Does NOT depend on Riverpod. Called externally by a stream subscriber.
class ContractualEvaluationEngine {
  final ContractualExecutionStateRepository _executionRepo;
  final SlaAuditLedgerRepository _ledgerRepo;

  /// Minimum dwell time inside the geofence before binding (seconds).
  static const int _minDwellSeconds = 30;

  /// Tracks when a vehicle first entered a SET's geofence.
  /// Key: setId, Value: first entry timestamp.
  final Map<String, DateTime> _firstEntryTimestamps = {};

  ContractualEvaluationEngine({
    required ContractualExecutionStateRepository executionRepo,
    required SlaAuditLedgerRepository ledgerRepo,
  }) : _executionRepo = executionRepo,
       _ledgerRepo = ledgerRepo;

  // ── Method 1: Process Vehicle Telemetry ─────────────────

  /// Evaluates a single vehicle state against all pending contractual
  /// obligations. Performs geofence detection and dwell-time binding.
  ///
  /// [nowUtc] is injectable for testability. Defaults to current UTC time.
  Future<void> processVehicleState(
    VehicleOperationalState vehicleState, {
    DateTime? nowUtc,
  }) async {
    final now = nowUtc ?? DateTime.now().toUtc();

    // 1. Find all pending execution states in their active window
    final pendingStates = await _executionRepo.findPendingInWindow(now);
    if (pendingStates.isEmpty) return;

    // 2. Filter by vehicle eligibility
    final eligible = pendingStates.where(
      (s) =>
          s.plannedVehicleId == null ||
          s.plannedVehicleId == vehicleState.vehicleId,
    );

    for (final state in eligible) {
      // 3. Calculate geofence distance
      final distance = _haversineMeters(
        vehicleState.latitude,
        vehicleState.longitude,
        state.startLatitude,
        state.startLongitude,
      );

      final insideGeofence = distance <= state.startRadiusMeters;

      if (insideGeofence) {
        // 4. Track dwell time
        final firstEntry = _firstEntryTimestamps.putIfAbsent(
          state.setId,
          () => now,
        );

        if (now.isBefore(firstEntry)) {
          // Out of order ping from before first entry. Ignore to avoid breaking dwell.
          continue;
        }

        final dwellDuration = now.difference(firstEntry);

        if (dwellDuration.inSeconds >= _minDwellSeconds) {
          // Check status again defensivelly against concurrent evaluations
          if (state.status != ExecutionStatus.pending) continue;

          // 5. Execute binding
          state.bindExecution(
            vehicleId: vehicleState.vehicleId,
            latitude: vehicleState.latitude,
            longitude: vehicleState.longitude,
            timestampUtc: now,
          );

          await _executionRepo.save(state);

          for (final event in state.domainEvents) {
            final entry = SlaLedgerMapper.mapToEntry(event);
            await _ledgerRepo.append(entry);
          }

          _firstEntryTimestamps.remove(state.setId);
        }
      } else {
        // Vehicle left the geofence — reset dwell timer
        // Only reset if this is NOT a delayed out-of-order ping from before the first entry
        final firstEntry = _firstEntryTimestamps[state.setId];
        if (firstEntry != null && now.isAfter(firstEntry)) {
          _firstEntryTimestamps.remove(state.setId);
        }
      }
    }
  }

  // ── Method 2: Sweep Expired Obligations ─────────────────

  /// Marks all expired pending obligations as NoShow.
  ///
  /// This method does NOT depend on telemetry — it should be called
  /// periodically by an external scheduler or subscriber.
  ///
  /// [nowUtc] is injectable for testability. Defaults to current UTC time.
  Future<void> sweepExpiredObligations({DateTime? nowUtc}) async {
    final now = nowUtc ?? DateTime.now().toUtc();

    final expiredStates = await _executionRepo.findExpiredPending(now);

    for (final state in expiredStates) {
      state.markNoShow(now);

      await _executionRepo.save(state);

      for (final event in state.domainEvents) {
        final entry = SlaLedgerMapper.mapToEntry(event);
        await _ledgerRepo.append(entry);
      }
    }
  }

  // ── Haversine ───────────────────────────────────────────

  /// Distance in metres between two lat/lng points.
  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}
