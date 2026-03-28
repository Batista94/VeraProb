import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/projections/providers/fleet_attention_projection_provider.dart';
import 'package:veraprob/application/projections/models/attention_state.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';

void main() {
  test('FleetAttentionProjectionProvider derives correct state', () async {
    final mockTrip = OperationalTrip(
      id: 'trip-1',
      vehicleId: 'v-1',
      routeId: 'r-1',
      scheduledStart: DateTime.now(),
      status: TripStatus.enRoute,
      severityScore: 0,
      delaySeconds: 0,
    );

    final mockState = VehicleOperationalState(
      vehicleId: 'v-1',
      tripId: 'trip-1',
      latitude: 0,
      longitude: 0,
      smoothedSpeed: 0,
      motionState: MotionState.moving,
      connectivityState: ConnectivityState.healthy,
      routeAdherence: RouteAdherence.onRoute,
      lastRawPingAt: DateTime.now(),
      stateChangedAt: DateTime.now(),
      confidence: 1.0,
      source: 'test',
    );

    final container = ProviderContainer(
      overrides: [
        enrichedTripsProvider.overrideWithValue([mockTrip]),
        normalizedStateProvider.overrideWith(
          (ref) => Stream.value([mockState]),
        ),
      ],
    );

    // Wait for StreamProvider to emit
    await container.read(normalizedStateProvider.future);
    final projection = container.read(fleetAttentionProjectionProvider);

    expect(
      projection.getContextFor('v-1').attentionState,
      AttentionState.normal,
    );
  });

  test(
    'FleetAttentionProjectionProvider activates focus mode when critical',
    () async {
      final mockTrip = OperationalTrip(
        id: 'trip-critical',
        vehicleId: 'v-crit',
        routeId: 'r-1',
        scheduledStart: DateTime.now(),
        status: TripStatus.interrupted,
        severityScore: 100,
        delaySeconds: 0,
      );

      final mockState = VehicleOperationalState(
        vehicleId: 'v-crit',
        tripId: 'trip-critical',
        latitude: 0,
        longitude: 0,
        smoothedSpeed: 0,
        motionState: MotionState.stopped,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: DateTime.now(),
        stateChangedAt: DateTime.now(),
        confidence: 1.0,
        source: 'test',
      );

      final container = ProviderContainer(
        overrides: [
          enrichedTripsProvider.overrideWithValue([mockTrip]),
          normalizedStateProvider.overrideWith(
            (ref) => Stream.value([mockState]),
          ),
        ],
      );

      await container.read(normalizedStateProvider.future);
      final projection = container.read(fleetAttentionProjectionProvider);

      expect(projection.isFocusModeActive, true);
      expect(
        projection.getContextFor('v-crit').attentionState,
        AttentionState.critical,
      );
    },
  );

  test('dimming occurs for normal vehicles when critical exists', () async {
    final trips = [
      OperationalTrip(
        id: 't-crit',
        vehicleId: 'v-crit',
        routeId: 'r-1',
        scheduledStart: DateTime.now(),
        status: TripStatus.interrupted,
      ),
      OperationalTrip(
        id: 't-norm',
        vehicleId: 'v-norm',
        routeId: 'r-2',
        scheduledStart: DateTime.now(),
        status: TripStatus.enRoute,
      ),
    ];

    final states = [
      VehicleOperationalState(
        vehicleId: 'v-crit',
        tripId: 't-crit',
        latitude: 0,
        longitude: 0,
        smoothedSpeed: 0,
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: DateTime.now(),
        stateChangedAt: DateTime.now(),
        confidence: 1.0,
        source: 'test',
      ),
      VehicleOperationalState(
        vehicleId: 'v-norm',
        tripId: 't-norm',
        latitude: 0,
        longitude: 0,
        smoothedSpeed: 0,
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: DateTime.now(),
        stateChangedAt: DateTime.now(),
        confidence: 1.0,
        source: 'test',
      ),
    ];

    final container = ProviderContainer(
      overrides: [
        enrichedTripsProvider.overrideWithValue(trips),
        normalizedStateProvider.overrideWith((ref) => Stream.value(states)),
      ],
    );

    await container.read(normalizedStateProvider.future);
    final projection = container.read(fleetAttentionProjectionProvider);

    expect(projection.isFocusModeActive, true);
    expect(projection.getContextFor('v-norm').opacityMultiplier, 0.6); // Dimmed
  });
}
