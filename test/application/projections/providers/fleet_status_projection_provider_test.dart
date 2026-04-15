import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/projections/providers/command_center_filter_provider.dart';
import 'package:veraprob/application/projections/providers/fleet_status_projection_provider.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/entities/operational_warning.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

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

OperationalWarning makeDelayWarning() => OperationalWarning(
  id: 'w-delay',
  type: 'DELAY', // must be uppercase — projection checks w.type == 'DELAY'
  message: 'Delay detected',
  severityScore: 30,
  detectedAt: DateTime.now().toUtc(),
);

OperationalTrip makeTrip({
  String id = 'trip1',
  String? vehicleId = 'v1',
  TripStatus status = TripStatus.enRoute,
  List<OperationalWarning> warnings = const [],
  int severityScore = 0,
  int delaySeconds = 0,
}) {
  return OperationalTrip(
    id: id,
    vehicleId: vehicleId,
    routeId: 'route1',
    status: status,
    scheduledStart: DateTime.now().toUtc(),
    warnings: List.unmodifiable(warnings), // immutability enforced
    severityScore: severityScore,
    delaySeconds: delaySeconds,
  );
}

ProviderContainer makeContainer({
  required List<VehicleOperationalState> states,
  required List<OperationalTrip> trips,
}) {
  return ProviderContainer(
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
  group('FleetStatusProjectionProvider', () {
    // ── Group 1: State Mapping (Criticality) ─────────────────────────────────
    group('State Mapping', () {
      test('healthy vehicle is placed in active bucket', () async {
        final container = makeContainer(
          states: [makeState()],
          trips: [makeTrip()],
        );
        addTearDown(container.dispose);
        await pumpStream(container);

        final proj = container.read(fleetStatusProjectionProvider);
        expect(proj.activeVehicles, hasLength(1));
        expect(proj.delayedVehicles, isEmpty);
        expect(proj.signalLostVehicles, isEmpty);
        expect(proj.offRouteVehicles, isEmpty);
      });

      test('vehicle with DELAY warning is placed in delayed bucket', () async {
        final container = makeContainer(
          states: [makeState(tripId: 'trip1')],
          trips: [
            makeTrip(id: 'trip1', warnings: [makeDelayWarning()]),
          ],
        );
        addTearDown(container.dispose);
        await pumpStream(container);

        final proj = container.read(fleetStatusProjectionProvider);
        expect(proj.delayedVehicles, hasLength(1));
        expect(proj.activeVehicles, isEmpty);
      });

      test('vehicle with signalLost is placed in signalLost bucket', () async {
        final container = makeContainer(
          states: [makeState(connectivityState: ConnectivityState.signalLost)],
          trips: [makeTrip()],
        );
        addTearDown(container.dispose);
        await pumpStream(container);

        final proj = container.read(fleetStatusProjectionProvider);
        expect(proj.signalLostVehicles, hasLength(1));
        expect(proj.activeVehicles, isEmpty);
      });

      test('vehicle offRoute is placed in offRoute bucket', () async {
        final container = makeContainer(
          states: [makeState(routeAdherence: RouteAdherence.offRoute)],
          trips: [makeTrip()],
        );
        addTearDown(container.dispose);
        await pumpStream(container);

        final proj = container.read(fleetStatusProjectionProvider);
        expect(proj.offRouteVehicles, hasLength(1));
        expect(proj.activeVehicles, isEmpty);
      });

      test(
        'mixed fleet: 4 vehicles are grouped into correct buckets',
        () async {
          final states = [
            makeState(vehicleId: 'v1', tripId: 'trip1'),
            makeState(
              vehicleId: 'v2',
              tripId: 'trip2',
              connectivityState: ConnectivityState.signalLost,
            ),
            makeState(
              vehicleId: 'v3',
              tripId: 'trip3',
              routeAdherence: RouteAdherence.offRoute,
            ),
            makeState(vehicleId: 'v4', tripId: 'trip4'),
          ];
          final trips = [
            makeTrip(id: 'trip1', vehicleId: 'v1'),
            makeTrip(id: 'trip2', vehicleId: 'v2'),
            makeTrip(id: 'trip3', vehicleId: 'v3'),
            makeTrip(
              id: 'trip4',
              vehicleId: 'v4',
              warnings: [makeDelayWarning()],
            ),
          ];
          final container = makeContainer(states: states, trips: trips);
          addTearDown(container.dispose);
          await pumpStream(container);

          final proj = container.read(fleetStatusProjectionProvider);
          expect(proj.activeVehicles, hasLength(1));
          expect(proj.signalLostVehicles, hasLength(1));
          expect(proj.offRouteVehicles, hasLength(1));
          expect(proj.delayedVehicles, hasLength(1));
          expect(proj.totalIssues, equals(3));
        },
      );

      test(
        'threshold crossing: adding DELAY warning moves vehicle from active to delayed',
        () async {
          // Phase 1: healthy trip — vehicle lands in active
          final healthyContainer = makeContainer(
            states: [makeState(tripId: 'trip1')],
            trips: [makeTrip(id: 'trip1')],
          );
          addTearDown(healthyContainer.dispose);
          await pumpStream(healthyContainer);
          expect(
            healthyContainer.read(fleetStatusProjectionProvider).activeVehicles,
            hasLength(1),
          );
          expect(
            healthyContainer
                .read(fleetStatusProjectionProvider)
                .delayedVehicles,
            isEmpty,
          );

          // Phase 2: same vehicle now has DELAY warning — must appear in delayed
          final delayedContainer = ProviderContainer(
            overrides: [
              normalizedStateProvider.overrideWith(
                (ref) => Stream.value([makeState(tripId: 'trip1')]),
              ),
              enrichedTripsProvider.overrideWith(
                (ref) => [
                  makeTrip(id: 'trip1', warnings: [makeDelayWarning()]),
                ],
              ),
            ],
          );
          addTearDown(delayedContainer.dispose);
          await pumpStream(delayedContainer);

          final proj = delayedContainer.read(fleetStatusProjectionProvider);
          expect(proj.delayedVehicles, hasLength(1));
          expect(proj.activeVehicles, isEmpty);
        },
      );
    });

    // ── Group 2: Stream Reactivity ────────────────────────────────────────────
    group('Stream Reactivity', () {
      test('emits new state when stream emits an additional vehicle', () async {
        final controller =
            StreamController<List<VehicleOperationalState>>.broadcast();
        addTearDown(controller.close);

        final container = ProviderContainer(
          overrides: [
            normalizedStateProvider.overrideWith((ref) => controller.stream),
            enrichedTripsProvider.overrideWith(
              (ref) => [
                makeTrip(id: 'trip1', vehicleId: 'v1'),
                makeTrip(id: 'trip2', vehicleId: 'v2'),
              ],
            ),
          ],
        );
        addTearDown(container.dispose);

        // Establish subscription BEFORE adding events so none are missed
        container.listen(normalizedStateProvider, (_, _) {});

        controller.add([makeState(vehicleId: 'v1', tripId: 'trip1')]);
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(fleetStatusProjectionProvider).activeVehicles,
          hasLength(1),
        );

        controller.add([
          makeState(vehicleId: 'v1', tripId: 'trip1'),
          makeState(vehicleId: 'v2', tripId: 'trip2'),
        ]);
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(fleetStatusProjectionProvider).activeVehicles,
          hasLength(2),
        );
      });

      test(
        'stale ping is processed without crash (temporal integrity is upstream concern)',
        () async {
          // Stale-data filtering is OperationalStateNormalizer's responsibility.
          // The projection provider is stateless and processes whatever arrives in the stream.
          final controller =
              StreamController<List<VehicleOperationalState>>.broadcast();
          addTearDown(controller.close);

          final now = DateTime.now().toUtc();
          final container = ProviderContainer(
            overrides: [
              normalizedStateProvider.overrideWith((ref) => controller.stream),
              enrichedTripsProvider.overrideWith((ref) => [makeTrip()]),
            ],
          );
          addTearDown(container.dispose);
          container.listen(normalizedStateProvider, (_, _) {});

          controller.add([makeState(lastRawPingAt: now)]);
          await Future<void>.delayed(Duration.zero);
          expect(
            container.read(fleetStatusProjectionProvider).activeVehicles,
            hasLength(1),
          );

          // Stale emission (older timestamp) — no crash, projection reflects the stream
          controller.add([
            makeState(lastRawPingAt: now.subtract(const Duration(seconds: 10))),
          ]);
          await Future<void>.delayed(Duration.zero);
          expect(
            () => container.read(fleetStatusProjectionProvider),
            returnsNormally,
          );
          expect(
            container.read(fleetStatusProjectionProvider).activeVehicles,
            hasLength(1),
          );
        },
      );
    });

    // ── Group 2.5: Consistency Audit (No-Leaks Guarantee) ────────────────────
    group('Consistency Audit', () {
      test(
        'partition sum equals total vehicles: every vehicle belongs to exactly one bucket',
        () async {
          // Mutually exclusive categories — one vehicle per bucket
          final states = [
            makeState(vehicleId: 'v1', tripId: 'trip1'), // → active
            makeState(
              vehicleId: 'v2',
              tripId: 'trip2',
              connectivityState: ConnectivityState.signalLost,
            ), // → signalLost
            makeState(
              vehicleId: 'v3',
              tripId: 'trip3',
              routeAdherence: RouteAdherence.offRoute,
            ), // → offRoute
            makeState(vehicleId: 'v4', tripId: 'trip4'), // → delayed
          ];
          final trips = [
            makeTrip(id: 'trip1', vehicleId: 'v1'),
            makeTrip(id: 'trip2', vehicleId: 'v2'),
            makeTrip(id: 'trip3', vehicleId: 'v3'),
            makeTrip(
              id: 'trip4',
              vehicleId: 'v4',
              warnings: [makeDelayWarning()],
            ),
          ];
          final container = makeContainer(states: states, trips: trips);
          addTearDown(container.dispose);
          await pumpStream(container);

          final proj = container.read(fleetStatusProjectionProvider);
          final partitionSum =
              proj.activeVehicles.length +
              proj.delayedVehicles.length +
              proj.signalLostVehicles.length +
              proj.offRouteVehicles.length;

          expect(
            partitionSum,
            equals(states.length),
            reason: 'No vehicle must be lost or double-counted across buckets',
          );
        },
      );
    });

    // ── Group 3: UI Resilience ────────────────────────────────────────────────
    group('UI Resilience', () {
      test('loading state returns safe empty default projection', () {
        final container = ProviderContainer(
          overrides: [
            normalizedStateProvider.overrideWith(
              (ref) => const Stream<List<VehicleOperationalState>>.empty(),
            ),
            enrichedTripsProvider.overrideWith((ref) => []),
          ],
        );
        addTearDown(container.dispose);
        // No pump — stream never emits, stays AsyncLoading

        final proj = container.read(fleetStatusProjectionProvider);
        expect(proj.activeVehicles, isEmpty);
        expect(proj.totalIssues, equals(0));
      });

      test(
        'stream error returns safe empty default without throwing',
        () async {
          final container = ProviderContainer(
            overrides: [
              normalizedStateProvider.overrideWith(
                (ref) => Stream<List<VehicleOperationalState>>.error(
                  Exception('network failure'),
                ),
              ),
              enrichedTripsProvider.overrideWith((ref) => []),
            ],
          );
          addTearDown(container.dispose);
          container.listen(normalizedStateProvider, (_, _) {});
          await Future<void>.delayed(Duration.zero);

          expect(
            () => container.read(fleetStatusProjectionProvider),
            returnsNormally,
          );
          final proj = container.read(fleetStatusProjectionProvider);
          expect(proj.activeVehicles, isEmpty);
          expect(proj.totalIssues, equals(0));
        },
      );
    });

    // ── Group 4: Filter Logic ─────────────────────────────────────────────────
    group('Filter Logic', () {
      test(
        'delayed filter surfaces only vehicles with TripStatus.delayed',
        () async {
          final states = [
            makeState(vehicleId: 'v1', tripId: 'trip1'),
            makeState(vehicleId: 'v2', tripId: 'trip2'),
          ];
          final trips = [
            makeTrip(id: 'trip1', vehicleId: 'v1', status: TripStatus.delayed),
            makeTrip(id: 'trip2', vehicleId: 'v2', status: TripStatus.enRoute),
          ];
          final container = ProviderContainer(
            overrides: [
              normalizedStateProvider.overrideWith(
                (ref) => Stream.value(states),
              ),
              enrichedTripsProvider.overrideWith((ref) => trips),
            ],
          );
          addTearDown(container.dispose);
          await pumpStream(container);

          container
              .read(commandCenterFilterProvider.notifier)
              .setStatusFilter(FleetStatusFilter.delayed);

          final proj = container.read(fleetStatusProjectionProvider);
          expect(proj.allFilteredVehicles, hasLength(1));
          expect(proj.allFilteredVehicles.first.vehicleId, equals('v1'));
        },
      );

      test(
        'alerts filter surfaces only vehicles with requiresAttention trip status',
        () async {
          final states = [
            makeState(vehicleId: 'v1', tripId: 'trip1'),
            makeState(vehicleId: 'v2', tripId: 'trip2'),
          ];
          final trips = [
            makeTrip(
              id: 'trip1',
              vehicleId: 'v1',
              status: TripStatus.interrupted, // requiresAttention = true
            ),
            makeTrip(
              id: 'trip2',
              vehicleId: 'v2',
              status: TripStatus.enRoute, // requiresAttention = false
            ),
          ];
          final container = ProviderContainer(
            overrides: [
              normalizedStateProvider.overrideWith(
                (ref) => Stream.value(states),
              ),
              enrichedTripsProvider.overrideWith((ref) => trips),
            ],
          );
          addTearDown(container.dispose);
          await pumpStream(container);

          container
              .read(commandCenterFilterProvider.notifier)
              .setStatusFilter(FleetStatusFilter.alerts);

          final proj = container.read(fleetStatusProjectionProvider);
          expect(proj.allFilteredVehicles, hasLength(1));
          expect(proj.allFilteredVehicles.first.vehicleId, equals('v1'));
        },
      );

      test(
        'filter transition delayed→all: correct count and no duplicates',
        () async {
          final states = [
            makeState(vehicleId: 'v1', tripId: 'trip1'),
            makeState(vehicleId: 'v2', tripId: 'trip2'),
          ];
          final trips = [
            makeTrip(id: 'trip1', vehicleId: 'v1', status: TripStatus.delayed),
            makeTrip(id: 'trip2', vehicleId: 'v2'),
          ];
          final container = ProviderContainer(
            overrides: [
              normalizedStateProvider.overrideWith(
                (ref) => Stream.value(states),
              ),
              enrichedTripsProvider.overrideWith((ref) => trips),
            ],
          );
          addTearDown(container.dispose);
          await pumpStream(container);

          // Phase 1: delayed filter — only v1 (with TripStatus.delayed)
          container
              .read(commandCenterFilterProvider.notifier)
              .setStatusFilter(FleetStatusFilter.delayed);

          var proj = container.read(fleetStatusProjectionProvider);
          expect(proj.allFilteredVehicles, hasLength(1));
          expect(proj.allFilteredVehicles.first.vehicleId, equals('v1'));

          // Phase 2: switch to all filter — both v1 and v2
          container
              .read(commandCenterFilterProvider.notifier)
              .setStatusFilter(FleetStatusFilter.all);

          proj = container.read(fleetStatusProjectionProvider);
          expect(proj.allFilteredVehicles, hasLength(2));

          // Verify no duplicates: length == set length
          final uniqueVehicles = proj.allFilteredVehicles
              .map((s) => s.vehicleId)
              .toSet();
          expect(
            proj.allFilteredVehicles.length,
            equals(uniqueVehicles.length),
            reason: 'No vehicle must appear twice in filtered list',
          );
        },
      );
    });
  });
}
