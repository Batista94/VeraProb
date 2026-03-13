import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pactaflow/application/simulation_control_service.dart';
import 'package:pactaflow/application/ports/contractual_event_port.dart';
import 'package:pactaflow/data/services/fleet_simulation_service.dart';
import 'package:pactaflow/domain/enums/trip_status.dart';
import 'package:pactaflow/domain/enums/event_type.dart';
import 'package:pactaflow/domain/entities/trip_event.dart';
import 'package:pactaflow/application/audit/audit_service.dart';

class MockFleetSimulationService extends Mock
    implements FleetSimulationService {}

class MockAuditService extends Mock implements AuditService {}

class MockContractualEventPort extends Mock implements ContractualEventPort {}

void main() {
  setUpAll(() {
    registerFallbackValue(EventType.statusChange);
    registerFallbackValue(TripStatus.enRoute);
  });

  group('SimulationControlService Actions', () {
    late SimulationControlService service;
    late MockFleetSimulationService mockSimulation;
    late MockAuditService mockAudit;
    late MockContractualEventPort mockEventPort;

    setUp(() {
      mockSimulation = MockFleetSimulationService();
      mockAudit = MockAuditService();
      mockEventPort = MockContractualEventPort();

      when(
        () => mockAudit.logAction(
          organizationId: any(named: 'organizationId'),
          operatorId: any(named: 'operatorId'),
          actionType: any(named: 'actionType'),
          entityId: any(named: 'entityId'),
          oldValue: any(named: 'oldValue'),
          newValue: any(named: 'newValue'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockEventPort.dispatchTripInterrupted(
          organizationId: any(named: 'organizationId'),
          tripId: any(named: 'tripId'),
          vehicleId: any(named: 'vehicleId'),
          operatorId: any(named: 'operatorId'),
          reason: any(named: 'reason'),
          occurredAtUtc: any(named: 'occurredAtUtc'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockEventPort.dispatchTripCancelled(
          organizationId: any(named: 'organizationId'),
          tripId: any(named: 'tripId'),
          vehicleId: any(named: 'vehicleId'),
          operatorId: any(named: 'operatorId'),
          reason: any(named: 'reason'),
          occurredAtUtc: any(named: 'occurredAtUtc'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockEventPort.dispatchOccurrenceRegistered(
          organizationId: any(named: 'organizationId'),
          tripId: any(named: 'tripId'),
          vehicleId: any(named: 'vehicleId'),
          operatorId: any(named: 'operatorId'),
          occurrenceType: any(named: 'occurrenceType'),
          notes: any(named: 'notes'),
          metadata: any(named: 'metadata'),
          occurredAtUtc: any(named: 'occurredAtUtc'),
        ),
      ).thenAnswer((_) async {});

      service = SimulationControlService(
        mockSimulation,
        mockAudit,
        mockEventPort,
        getOperatorId: () => 'test_operator',
        getOrganizationId: () => 'org-1',
      );
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

        // Verify no contractual event was dispatched (Regularize is operational, not forensic)
        verifyNever(
          () => mockEventPort.dispatchTripInterrupted(
            organizationId: any(named: 'organizationId'),
            tripId: any(named: 'tripId'),
            vehicleId: any(named: 'vehicleId'),
            operatorId: any(named: 'operatorId'),
            reason: any(named: 'reason'),
            occurredAtUtc: any(named: 'occurredAtUtc'),
          ),
        );
        verifyNever(
          () => mockEventPort.dispatchTripCancelled(
            organizationId: any(named: 'organizationId'),
            tripId: any(named: 'tripId'),
            vehicleId: any(named: 'vehicleId'),
            operatorId: any(named: 'operatorId'),
            reason: any(named: 'reason'),
            occurredAtUtc: any(named: 'occurredAtUtc'),
          ),
        );
      },
    );

    test('Cancelar updates status and dispatches contractual evidence', () async {
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

      verify(
        () => mockSimulation.updateTripStatus('t_2', TripStatus.cancelled),
      ).called(1);

      // Verify the port received the cancellation evidence
      verify(
        () => mockEventPort.dispatchTripCancelled(
          organizationId: any(named: 'organizationId'),
          tripId: any(named: 'tripId'),
          vehicleId: any(named: 'vehicleId'),
          operatorId: any(named: 'operatorId'),
          reason: any(named: 'reason'),
          occurredAtUtc: any(named: 'occurredAtUtc'),
        ),
      ).called(1);
    });

    test('Ocurrence dispatches contractual evidence via port', () async {
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
          id: '3',
          tripId: 't_3',
          eventType: EventType.manualOverride,
          createdAt: DateTime.now(),
        ),
      );

      await service.createTripEvent(
        't_3',
        EventType.manualOverride,
        metadata: {'type': 'Accident'},
        notes: 'Test occurrence',
      );

      verify(
        () => mockEventPort.dispatchOccurrenceRegistered(
          organizationId: any(named: 'organizationId'),
          tripId: any(named: 'tripId'),
          vehicleId: any(named: 'vehicleId'),
          operatorId: any(named: 'operatorId'),
          occurrenceType: any(named: 'occurrenceType'),
          notes: any(named: 'notes'),
          metadata: any(named: 'metadata'),
          occurredAtUtc: any(named: 'occurredAtUtc'),
        ),
      ).called(1);
    });
  });
}
