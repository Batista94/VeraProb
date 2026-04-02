import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/intelligence/situation_engine.dart';
import 'package:veraprob/application/operational_control_service.dart';
import 'package:veraprob/data/services/fleet_simulation_service.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/application/projections/providers/fleet_attention_projection_provider.dart';
import 'package:veraprob/application/projections/models/attention_state.dart';

class MockFleetSimulationService extends Mock
    implements FleetSimulationService {}

class MockSituationEngine extends Mock implements SituationEngine {}

class MockOperationalControlService extends Mock
    implements OperationalControlService {}

class MockFleetAttentionProjection extends Mock
    implements FleetAttentionProjection {}

class MockAttentionContext extends Mock implements AttentionContext {}

void main() {
  late MockFleetSimulationService mockSimulation;
  late MockSituationEngine mockEngine;
  late MockOperationalControlService mockControl;
  late MockFleetAttentionProjection mockAttention;

  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
    registerFallbackValue(<String, VehicleOperationalState>{});
    registerFallbackValue(MockOperationalControlService());
  });

  setUp(() {
    mockSimulation = MockFleetSimulationService();
    mockEngine = MockSituationEngine();
    mockControl = MockOperationalControlService();
    mockAttention = MockFleetAttentionProjection();

    // Default behaviors
    when(
      () => mockSimulation.tripStream(interval: any(named: 'interval')),
    ).thenAnswer((_) => Stream.value([]));
    when(() => mockAttention.getContextFor(any())).thenReturn(
      const AttentionContext(
        attentionState: AttentionState.normal,
        opacityMultiplier: 1.0,
        isPulsing: false,
      ),
    );
  });

  ProviderContainer makeContainer({
    List<OperationalTrip>? rawTrips,
    List<OperationalTrip>? enrichedTrips,
    String? orgId,
  }) {
    return ProviderContainer(
      overrides: [
        fleetSimulationProvider.overrideWithValue(mockSimulation),
        situationEngineProvider.overrideWithValue(mockEngine),
        operationalControlProvider.overrideWithValue(mockControl),
        fleetAttentionProjectionProvider.overrideWithValue(mockAttention),
        if (orgId != null)
          currentOrganizationIdProvider.overrideWithValue(orgId),
        if (rawTrips != null)
          tripStreamProvider.overrideWith((ref) => Stream.value(rawTrips)),
        if (enrichedTrips != null)
          enrichedTripsProvider.overrideWithValue(enrichedTrips),
      ],
    );
  }

  group('fleetSummaryProvider', () {
    test('returns empty summary when no trips exist', () {
      final container = makeContainer(rawTrips: [], enrichedTrips: []);

      final summary = container.read(fleetSummaryProvider);
      expect(summary.totalActive, 0);
      expect(summary.onTime, 0);
      expect(summary.delayed, 0);
    });

    test('calculates correct KPIs for mixed fleet', () {
      final now = DateTime.now().toUtc();
      final trip1 = OperationalTrip(
        id: 't1',
        routeId: 'r1',
        scheduledStart: now,
        status: TripStatus.enRoute,
        delaySeconds: 0,
        severityScore: 0,
        vehicleId: 'v1',
      );
      final trip2 = OperationalTrip(
        id: 't2',
        routeId: 'r1',
        scheduledStart: now,
        status: TripStatus.delayed,
        delaySeconds: 600, // 10 min
        severityScore: 10,
        vehicleId: 'v2',
      );
      final trip3 = OperationalTrip(
        id: 't3',
        routeId: 'r1',
        scheduledStart: now,
        status: TripStatus.atStop,
        delaySeconds: 0,
        severityScore: 0,
        vehicleId: 'v3',
      );

      final container = makeContainer(enrichedTrips: [trip1, trip2, trip3]);

      final summary = container.read(fleetSummaryProvider);
      expect(summary.totalActive, 3);
      expect(summary.onTime, 2); // t1 (enRoute), t3 (atStop)
      expect(summary.delayed, 1); // t2
      expect(summary.atStop, 1); // t3
      expect(summary.avgDelayMinutes, 10);
    });
  });

  group('UI interactions', () {
    test('triggerUIRefresh increments counter', () {
      final container = ProviderContainer();
      final initial = container.read(uiRefreshTrigger);
      container.read(uiRefreshTrigger.notifier).state++;
      expect(container.read(uiRefreshTrigger), initial + 1);
    });
  });

  group('stressScenarioProvider', () {
    test('provides config', () {
      final container = ProviderContainer();
      final config = container.read(stressScenarioProvider);
      expect(config, isNotNull);
    });
  });
}
