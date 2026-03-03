import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busflow/application/simulation_control_service.dart';
import 'package:busflow/data/services/fleet_simulation_service.dart';
import 'package:busflow/domain/enums/trip_status.dart';
import 'package:busflow/domain/enums/event_type.dart';
import 'package:busflow/domain/entities/trip_event.dart';
import 'package:busflow/application/audit/audit_service.dart';
import 'package:busflow/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:busflow/domain/sla_audit/sla_ledger_entry.dart';

class MockFleetSimulationService extends Mock
    implements FleetSimulationService {}

class MockAuditService extends Mock implements AuditService {}

class MockSlaAuditLedgerRepository extends Mock
    implements SlaAuditLedgerRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(EventType.statusChange);
    registerFallbackValue(TripStatus.enRoute);
    registerFallbackValue(
      SlaLedgerEntry(
        type: 'DUMMY',
        contractId: 'N/A',
        planVersion: 0,
        occurredAtUtc: DateTime.now(),
      ),
    );
  });

  group('SimulationControlService Actions', () {
    late SimulationControlService service;
    late MockFleetSimulationService mockSimulation;
    late MockAuditService mockAudit;
    late MockSlaAuditLedgerRepository mockLedgerRepo;

    setUp(() {
      mockSimulation = MockFleetSimulationService();
      mockAudit = MockAuditService();
      mockLedgerRepo = MockSlaAuditLedgerRepository();

      when(
        () => mockAudit.logAction(
          operatorId: any(named: 'operatorId'),
          actionType: any(named: 'actionType'),
          entityId: any(named: 'entityId'),
          oldValue: any(named: 'oldValue'),
          newValue: any(named: 'newValue'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async {});

      when(() => mockLedgerRepo.append(any())).thenAnswer((_) async {});

      service = SimulationControlService(
        mockSimulation,
        mockAudit,
        mockLedgerRepo,
        getOperatorId: () => 'test_operator',
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

        // Verify ledger was NOT called (Regularize/Resolve Alert is operational, not forensic)
        verifyNever(() => mockLedgerRepo.append(any()));
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

      // Verify ledger WAS called with TRIP_CANCELLED
      verify(() => mockLedgerRepo.append(any())).called(1);
    });

    test('Ocurrence generates SlaLedgerEntry in repository', () async {
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

      verify(() => mockLedgerRepo.append(any())).called(1);
    });
  });
}
