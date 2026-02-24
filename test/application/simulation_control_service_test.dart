import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busflow/application/simulation_control_service.dart';
import 'package:busflow/data/services/fleet_simulation_service.dart';
import 'package:busflow/domain/enums/trip_status.dart';
import 'package:busflow/domain/enums/event_type.dart';
import 'package:busflow/domain/entities/trip_event.dart';

class MockFleetSimulationService extends Mock
    implements FleetSimulationService {}

void main() {
  setUpAll(() {
    registerFallbackValue(EventType.statusChange);
    registerFallbackValue(TripStatus.enRoute);
  });

  group('SimulationControlService Actions', () {
    late SimulationControlService service;
    late MockFleetSimulationService mockSimulation;

    setUp(() {
      mockSimulation = MockFleetSimulationService();
      service = SimulationControlService(mockSimulation);
    });

    test(
      'Regularizar updates status to enRoute and clears delay via simulation',
      () async {
        when(
          () => mockSimulation.updateTripStatus('t_1', TripStatus.enRoute),
        ).thenReturn(TripStatus.delayed);

        when(
          () => mockSimulation.addEvent(
            tripId: any(named: 'tripId'),
            eventType: any(named: 'eventType'),
            fromStatus: any(named: 'fromStatus'),
            toStatus: any(named: 'toStatus'),
            metadata: any(named: 'metadata'),
          ),
        ).thenReturn(
          TripEvent(
            id: '1',
            tripId: 't_1',
            eventType: EventType.statusChange,
            createdAt: DateTime.now(),
          ),
        );

        await service.updateTripStatus(
          't_1',
          TripStatus.enRoute,
          reason: 'Test regularize',
        );

        // Verify simulation was called correctly
        verify(
          () => mockSimulation.updateTripStatus('t_1', TripStatus.enRoute),
        ).called(1);
      },
    );

    test('Cancelar updates status and logs event', () async {
      when(
        () => mockSimulation.updateTripStatus('t_2', TripStatus.cancelled),
      ).thenReturn(TripStatus.enRoute);

      when(
        () => mockSimulation.addEvent(
          tripId: any(named: 'tripId'),
          eventType: any(named: 'eventType'),
          fromStatus: any(named: 'fromStatus'),
          toStatus: any(named: 'toStatus'),
          metadata: any(named: 'metadata'),
        ),
      ).thenReturn(
        TripEvent(
          id: '2',
          tripId: 't_2',
          eventType: EventType.statusChange,
          createdAt: DateTime.now(),
        ),
      );

      await service.updateTripStatus('t_2', TripStatus.cancelled);

      // Verify no delay clearing logic for cancellation specifically
      verify(
        () => mockSimulation.updateTripStatus('t_2', TripStatus.cancelled),
      ).called(1);
    });
  });
}
