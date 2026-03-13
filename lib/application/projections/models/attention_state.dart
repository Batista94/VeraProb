import 'package:pactaflow/domain/enums/trip_status.dart';
import 'package:pactaflow/domain/enums/connectivity_state.dart';
import 'package:pactaflow/domain/enums/route_adherence.dart';

/// Operational attention level for a vehicle in the Command Center.
///
/// This is a **Projection Layer concept** — it does NOT exist in the Domain.
/// It is derived deterministically from domain signals and must never be
/// stored or mutated. It exists solely so the Presentation Layer can
/// distinguish between operational variance (delay) and true emergencies.
///
/// Derivation rule: [deriveAttentionState]
enum AttentionState {
  /// Vehicle operating normally, no operator action needed.
  normal,

  /// Operational variance detected (e.g. delay). Monitor but don't alarm.
  warning,

  /// True emergency requiring immediate operator intervention.
  critical,
}

/// Pure, deterministic derivation of [AttentionState] from domain signals.
///
/// This function is the **single source of truth** for attention classification.
/// It must remain side-effect-free and stateless.
///
/// Priority order (first match wins):
/// 1. Signal lost → CRITICAL
/// 2. Off-route → CRITICAL
/// 3. Status is interrupted/noShow/maintenance → CRITICAL
/// 4. Severity score ≥ 50 → CRITICAL
/// 5. Status is delayed → WARNING
/// 6. Severity score ≥ 30 → WARNING
/// 7. Everything else → NORMAL
AttentionState deriveAttentionState({
  required TripStatus status,
  required int severityScore,
  required ConnectivityState connectivity,
  required RouteAdherence adherence,
}) {
  // ── CRITICAL: True emergencies ─────────────────────────
  if (connectivity == ConnectivityState.signalLost) {
    return AttentionState.critical;
  }
  if (adherence == RouteAdherence.offRoute) {
    return AttentionState.critical;
  }
  switch (status) {
    case TripStatus.interrupted:
    case TripStatus.noShow:
    case TripStatus.maintenance:
      return AttentionState.critical;
    default:
      break;
  }
  if (severityScore >= 50) {
    return AttentionState.critical;
  }

  // ── WARNING: Operational variance ──────────────────────
  if (status == TripStatus.delayed) {
    return AttentionState.warning;
  }
  if (severityScore >= 30) {
    return AttentionState.warning;
  }

  // ── NORMAL ─────────────────────────────────────────────
  return AttentionState.normal;
}
