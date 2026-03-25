import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/projections/models/attention_state.dart';
import 'package:veraprob/domain/enums/connectivity_state.dart';
import 'package:veraprob/domain/enums/route_adherence.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

void main() {
  group('deriveAttentionState', () {
    // Helper for the common "normal" baseline
    AttentionState derive({
      TripStatus status = TripStatus.enRoute,
      int severityScore = 0,
      ConnectivityState connectivity = ConnectivityState.healthy,
      RouteAdherence adherence = RouteAdherence.onRoute,
    }) => deriveAttentionState(
      status: status,
      severityScore: severityScore,
      connectivity: connectivity,
      adherence: adherence,
    );

    // ── CRITICAL path ──────────────────────────────────────────────────────

    test('signal lost → CRITICAL regardless of other signals', () {
      expect(
        derive(connectivity: ConnectivityState.signalLost),
        AttentionState.critical,
      );
    });

    test('off-route → CRITICAL even when status is normal', () {
      expect(
        derive(adherence: RouteAdherence.offRoute),
        AttentionState.critical,
      );
    });

    test('status interrupted → CRITICAL', () {
      expect(derive(status: TripStatus.interrupted), AttentionState.critical);
    });

    test('status noShow → CRITICAL', () {
      expect(derive(status: TripStatus.noShow), AttentionState.critical);
    });

    test('status maintenance → CRITICAL', () {
      expect(derive(status: TripStatus.maintenance), AttentionState.critical);
    });

    test('severity score exactly 50 → CRITICAL', () {
      expect(derive(severityScore: 50), AttentionState.critical);
    });

    test('severity score above 50 → CRITICAL', () {
      expect(derive(severityScore: 99), AttentionState.critical);
    });

    // ── Signal-lost overrides other signals ───────────────────────────────

    test('signal lost overrides delayed status → CRITICAL not WARNING', () {
      expect(
        derive(
          connectivity: ConnectivityState.signalLost,
          status: TripStatus.delayed,
        ),
        AttentionState.critical,
      );
    });

    test('off-route overrides delayed status → CRITICAL not WARNING', () {
      expect(
        derive(adherence: RouteAdherence.offRoute, status: TripStatus.delayed),
        AttentionState.critical,
      );
    });

    // ── WARNING path ───────────────────────────────────────────────────────

    test('status delayed → WARNING', () {
      expect(derive(status: TripStatus.delayed), AttentionState.warning);
    });

    test('severity score exactly 30 → WARNING', () {
      expect(derive(severityScore: 30), AttentionState.warning);
    });

    test('severity score between 30 and 49 → WARNING', () {
      expect(derive(severityScore: 40), AttentionState.warning);
    });

    test('severity score 29 → NORMAL (below warning threshold)', () {
      expect(derive(severityScore: 29), AttentionState.normal);
    });

    // ── NORMAL path ────────────────────────────────────────────────────────

    test('all normal signals → NORMAL', () {
      expect(
        derive(
          status: TripStatus.enRoute,
          severityScore: 0,
          connectivity: ConnectivityState.healthy,
          adherence: RouteAdherence.onRoute,
        ),
        AttentionState.normal,
      );
    });

    test(
      'minor deviation with healthy connectivity and low severity → NORMAL',
      () {
        expect(
          derive(adherence: RouteAdherence.minorDeviation, severityScore: 10),
          AttentionState.normal,
        );
      },
    );

    test(
      'degraded connectivity alone does not trigger WARNING or CRITICAL',
      () {
        expect(
          derive(connectivity: ConnectivityState.degraded),
          AttentionState.normal,
        );
      },
    );

    test('completed status with score 0 → NORMAL', () {
      expect(
        derive(status: TripStatus.completed, severityScore: 0),
        AttentionState.normal,
      );
    });
  });
}
