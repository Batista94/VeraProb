import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/projections/models/attention_state.dart';
import 'package:veraprob/application/projections/providers/fleet_attention_projection_provider.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────
//
// SAFETY: TripStatus values `dispatched`, `offline`, and `detour` are NOT
// present in TripStatusView. Using them will cause `_mapToView()` to throw.
// Only use: scheduled, enRoute, delayed, atStop, interrupted, noShow,
//           maintenance, completed, cancelled.

VehicleOperationalState makeState({
  String vehicleId = 'v1',
  String tripId = 'trip1',
  ConnectivityState connectivityState = ConnectivityState.healthy,
  RouteAdherence routeAdherence = RouteAdherence.onRoute,
  MotionState motionState = MotionState.moving,
  double smoothedSpeed = 40.0, // Physical Metric - Double Required
  DateTime? lastRawPingAt,
}) {
  final now = DateTime.now().toUtc();
  return VehicleOperationalState(
    rawSpeed: 0.0,
    vehicleId: vehicleId,
    tripId: tripId,
    latitude: -20.0, // Physical Metric - Double Required
    longitude: -40.0, // Physical Metric - Double Required
    smoothedSpeed: smoothedSpeed, // Physical Metric - Double Required
    motionState: motionState,
    connectivityState: connectivityState,
    routeAdherence: routeAdherence,
    lastRawPingAt: lastRawPingAt ?? now,
    stateChangedAt: now,
    confidence: 1.0, // Physical Metric - Double Required
    source: 'test',
  );
}

OperationalTrip makeTrip({
  String id = 'trip1',
  String? vehicleId = 'v1',
  TripStatus status =
      TripStatus.enRoute, // safe default — present in TripStatusView
  int severityScore = 0,
}) {
  return OperationalTrip(
    id: id,
    vehicleId: vehicleId,
    routeId: 'route1',
    status: status,
    scheduledStart: DateTime.now().toUtc(),
    warnings: List.unmodifiable(const []), // immutability enforced
    severityScore: severityScore,
  );
}

ProviderContainer makeContainer({
  required List<VehicleOperationalState> states,
  required List<OperationalTrip> trips,
}) {
  return ProviderContainer.test(
    overrides: [
      normalizedStateProvider.overrideWith((ref) => Stream.value(states)),
      enrichedTripsProvider.overrideWith((ref) => trips),
    ],
  );
}

/// Establishes a stream subscription and pumps the event loop so that
/// [normalizedStateProvider] transitions from AsyncLoading → AsyncData
/// before the test makes assertions.
Future<void> pumpStream(ProviderContainer container) async {
  // listen() keeps the subscription alive so Stream.value() emission is not lost.
  container.listen(normalizedStateProvider, (_, _) {});
  await Future<void>.delayed(Duration.zero);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FleetAttentionProjectionProvider', () {
    // ── Group 1: State Mapping (Criticality) ─────────────────────────────────
    group('State Mapping', () {
      test('signalLost connectivity → CRITICAL', () async {
        final container = makeContainer(
          states: [makeState(connectivityState: ConnectivityState.signalLost)],
          trips: [makeTrip()],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.critical),
        );
      });

      test('offRoute adherence → CRITICAL', () async {
        final container = makeContainer(
          states: [makeState(routeAdherence: RouteAdherence.offRoute)],
          trips: [makeTrip()],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.critical),
        );
      });

      test('interrupted trip status → CRITICAL', () async {
        final container = makeContainer(
          states: [makeState()],
          trips: [makeTrip(status: TripStatus.interrupted)],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.critical),
        );
      });

      test('noShow trip status → CRITICAL', () async {
        final container = makeContainer(
          states: [makeState()],
          trips: [makeTrip(status: TripStatus.noShow)],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.critical),
        );
      });

      test('severity ≥ 50 → CRITICAL', () async {
        final container = makeContainer(
          states: [makeState()],
          trips: [makeTrip(severityScore: 50)],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.critical),
        );
      });

      test('delayed trip status → WARNING', () async {
        final container = makeContainer(
          states: [makeState()],
          trips: [makeTrip(status: TripStatus.delayed)],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.warning),
        );
      });

      test('severity ≥ 30 but < 50 → WARNING', () async {
        final container = makeContainer(
          states: [makeState()],
          trips: [makeTrip(severityScore: 30)],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.warning),
        );
      });

      test('healthy vehicle with no issues → NORMAL', () async {
        final container = makeContainer(
          states: [makeState()],
          trips: [makeTrip()],
        );
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').attentionState,
          equals(AttentionState.normal),
        );
      });
    });

    // ── Group 2: Stream Reactivity ────────────────────────────────────────────
    group('Stream Reactivity', () {
      test(
        'new position triggers re-projection: NORMAL → CRITICAL on signalLost',
        () async {
          final controller =
              StreamController<List<VehicleOperationalState>>.broadcast();
          addTearDown(controller.close);

          final container = ProviderContainer.test(
            overrides: [
              normalizedStateProvider.overrideWith((ref) => controller.stream),
              enrichedTripsProvider.overrideWith((ref) => [makeTrip()]),
            ],
          );

          // Establish subscription BEFORE adding events so none are missed
          container.listen(normalizedStateProvider, (_, _) {});

          // Initial: healthy state → NORMAL
          controller.add([makeState()]);
          await Future<void>.delayed(Duration.zero);
          expect(
            container
                .read(fleetAttentionProjectionProvider)
                .getContextFor('v1')
                .attentionState,
            equals(AttentionState.normal),
          );

          // Signal lost → must re-project to CRITICAL
          controller.add([
            makeState(connectivityState: ConnectivityState.signalLost),
          ]);
          await Future<void>.delayed(Duration.zero);
          expect(
            container
                .read(fleetAttentionProjectionProvider)
                .getContextFor('v1')
                .attentionState,
            equals(AttentionState.critical),
          );
        },
      );

      test(
        'stale ping is processed without crash (temporal integrity is upstream concern)',
        () async {
          // Stale-data filtering is OperationalStateNormalizer's responsibility.
          // The attention projection is stateless and faithfully processes whatever the stream provides.
          final controller =
              StreamController<List<VehicleOperationalState>>.broadcast();
          addTearDown(controller.close);

          final now = DateTime.now().toUtc();
          final container = ProviderContainer.test(
            overrides: [
              normalizedStateProvider.overrideWith((ref) => controller.stream),
              enrichedTripsProvider.overrideWith((ref) => [makeTrip()]),
            ],
          );

          // Establish subscription BEFORE adding events so none are missed
          container.listen(normalizedStateProvider, (_, _) {});

          // Fresh emission
          controller.add([makeState(lastRawPingAt: now)]);
          await Future<void>.delayed(Duration.zero);
          expect(
            container
                .read(fleetAttentionProjectionProvider)
                .getContextFor('v1')
                .attentionState,
            equals(AttentionState.normal),
          );

          // Stale emission (older timestamp) — no crash, projection processes data normally
          controller.add([
            makeState(lastRawPingAt: now.subtract(const Duration(seconds: 30))),
          ]);
          await Future<void>.delayed(Duration.zero);
          expect(
            () => container.read(fleetAttentionProjectionProvider),
            returnsNormally,
          );
          expect(
            container
                .read(fleetAttentionProjectionProvider)
                .getContextFor('v1')
                .attentionState,
            equals(AttentionState.normal),
          );
        },
      );
    });

    // ── Group 3: UI Resilience & Focus Mode ──────────────────────────────────
    group('UI Resilience & Focus Mode', () {
      test('no data (loading) → empty projection with focus mode off', () {
        final container = ProviderContainer.test(
          overrides: [
            normalizedStateProvider.overrideWith(
              (ref) => const Stream<List<VehicleOperationalState>>.empty(),
            ),
            enrichedTripsProvider.overrideWith((ref) => []),
          ],
        );
        // No pump — stream never emits, stays AsyncLoading

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(proj.isFocusModeActive, isFalse);
        expect(proj.vehicleStates, isEmpty);
      });

      test(
        'stream error returns safe empty default without throwing',
        () async {
          final container = ProviderContainer.test(
            overrides: [
              normalizedStateProvider.overrideWith(
                (ref) => Stream<List<VehicleOperationalState>>.error(
                  Exception('network failure'),
                ),
              ),
              enrichedTripsProvider.overrideWith((ref) => []),
            ],
          );
          container.listen(normalizedStateProvider, (_, _) {});
          await Future<void>.delayed(Duration.zero);

          expect(
            () => container.read(fleetAttentionProjectionProvider),
            returnsNormally,
          );
          final proj = container.read(fleetAttentionProjectionProvider);
          expect(proj.isFocusModeActive, isFalse);
          expect(proj.vehicleStates, isEmpty);
        },
      );

      test('focus mode activates when ANY vehicle is CRITICAL', () async {
        final states = [
          makeState(
            vehicleId: 'v1',
            tripId: 'trip1',
            connectivityState: ConnectivityState.signalLost, // → CRITICAL
          ),
          makeState(vehicleId: 'v2', tripId: 'trip2'), // → NORMAL
        ];
        final trips = [
          makeTrip(id: 'trip1', vehicleId: 'v1'),
          makeTrip(id: 'trip2', vehicleId: 'v2'),
        ];
        final container = makeContainer(states: states, trips: trips);
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(proj.isFocusModeActive, isTrue);
        expect(proj.getContextFor('v1').isPulsing, isTrue);
        expect(proj.getContextFor('v1').opacityMultiplier, equals(1.0));
        expect(
          proj.getContextFor('v2').attentionState,
          equals(AttentionState.normal),
        );
        expect(proj.getContextFor('v2').opacityMultiplier, equals(0.6));
        expect(proj.getContextFor('v2').isPulsing, isFalse);
      });

      test(
        'focus mode is OFF when no CRITICAL vehicles — all at full opacity',
        () async {
          final states = [
            makeState(vehicleId: 'v1', tripId: 'trip1'),
            makeState(vehicleId: 'v2', tripId: 'trip2'),
          ];
          final trips = [
            makeTrip(id: 'trip1', vehicleId: 'v1'),
            makeTrip(id: 'trip2', vehicleId: 'v2'),
          ];
          final container = makeContainer(states: states, trips: trips);
          await pumpStream(container);

          final proj = container.read(fleetAttentionProjectionProvider);
          expect(proj.isFocusModeActive, isFalse);
          expect(proj.getContextFor('v1').opacityMultiplier, equals(1.0));
          expect(proj.getContextFor('v2').opacityMultiplier, equals(1.0));
        },
      );

      test(
        'WARNING vehicle dims to 0.85 opacity when a CRITICAL vehicle is present',
        () async {
          final states = [
            makeState(
              vehicleId: 'v1',
              tripId: 'trip1',
              connectivityState: ConnectivityState.signalLost, // → CRITICAL
            ),
            makeState(vehicleId: 'v2', tripId: 'trip2'), // → WARNING via status
          ];
          final trips = [
            makeTrip(id: 'trip1', vehicleId: 'v1'),
            makeTrip(id: 'trip2', vehicleId: 'v2', status: TripStatus.delayed),
          ];
          final container = makeContainer(states: states, trips: trips);
          await pumpStream(container);

          final proj = container.read(fleetAttentionProjectionProvider);
          expect(proj.isFocusModeActive, isTrue);
          expect(
            proj.getContextFor('v2').attentionState,
            equals(AttentionState.warning),
          );
          expect(proj.getContextFor('v2').opacityMultiplier, equals(0.85));
          expect(proj.getContextFor('v2').isPulsing, isFalse);
        },
      );
    });

    // ── Group 4: Filter Logic ─────────────────────────────────────────────────
    group('Filter Logic', () {
      test('only CRITICAL vehicles have isPulsing = true', () async {
        final states = [
          makeState(
            vehicleId: 'v1',
            tripId: 'trip1',
            connectivityState: ConnectivityState.signalLost, // CRITICAL
          ),
          makeState(vehicleId: 'v2', tripId: 'trip2'), // WARNING via status
          makeState(vehicleId: 'v3', tripId: 'trip3'), // NORMAL
        ];
        final trips = [
          makeTrip(id: 'trip1', vehicleId: 'v1'),
          makeTrip(id: 'trip2', vehicleId: 'v2', status: TripStatus.delayed),
          makeTrip(id: 'trip3', vehicleId: 'v3'),
        ];
        final container = makeContainer(states: states, trips: trips);
        await pumpStream(container);

        final proj = container.read(fleetAttentionProjectionProvider);
        expect(
          proj.getContextFor('v1').isPulsing,
          isTrue,
          reason: 'CRITICAL must pulse',
        );
        expect(
          proj.getContextFor('v2').isPulsing,
          isFalse,
          reason: 'WARNING must not pulse',
        );
        expect(
          proj.getContextFor('v3').isPulsing,
          isFalse,
          reason: 'NORMAL must not pulse',
        );
      });

      test(
        'getContextFor maps each vehicleId to its correct AttentionContext',
        () async {
          final states = [
            makeState(
              vehicleId: 'v1',
              tripId: 'trip1',
              connectivityState: ConnectivityState.signalLost,
            ),
            makeState(vehicleId: 'v2', tripId: 'trip2'),
            makeState(vehicleId: 'v3', tripId: 'trip3'),
          ];
          final trips = [
            makeTrip(id: 'trip1', vehicleId: 'v1'),
            makeTrip(id: 'trip2', vehicleId: 'v2', status: TripStatus.delayed),
            makeTrip(id: 'trip3', vehicleId: 'v3'),
          ];
          final container = makeContainer(states: states, trips: trips);
          await pumpStream(container);

          final proj = container.read(fleetAttentionProjectionProvider);
          expect(
            proj.getContextFor('v1').attentionState,
            equals(AttentionState.critical),
          );
          expect(
            proj.getContextFor('v2').attentionState,
            equals(AttentionState.warning),
          );
          expect(
            proj.getContextFor('v3').attentionState,
            equals(AttentionState.normal),
          );

          // Unknown vehicleId falls back to normal context (safe default)
          expect(
            proj.getContextFor('unknown').attentionState,
            equals(AttentionState.normal),
          );
          expect(proj.getContextFor('unknown').isPulsing, isFalse);
        },
      );
    });
  });
}
