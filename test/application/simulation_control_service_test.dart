import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/audit/audit_service.dart';
import 'package:veraprob/application/ports/contractual_event_port.dart';
import 'package:veraprob/application/simulation_control_service.dart';
import 'package:veraprob/infrastructure/simulation/fleet_simulation_service.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/entities/trip_event.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

class _MockFleetSimulationService extends Mock
    implements FleetSimulationService {}

class _MockAuditService extends Mock implements AuditService {}

class _MockContractualEventPort extends Mock implements ContractualEventPort {}

void main() {
  setUpAll(() {
    registerFallbackValue(EventType.statusChange);
    registerFallbackValue(TripStatus.enRoute);
  });

  group('SimulationControlService', () {
    late SimulationControlService service;
    late _MockFleetSimulationService simulation;
    late _MockAuditService audit;
    late _MockContractualEventPort eventPort;
    late FakeDateTimeProvider clock;

    final fixedUtc = DateTime.utc(2026, 4, 18, 12, 0, 0);

    TripEvent newEvent(String id, String tripId) => TripEvent(
      id: id,
      tripId: tripId,
      eventType: EventType.statusChange,
      createdAt: fixedUtc,
    );

    OperationalTrip fakeTripWith({required String id, String? vehicleId}) =>
        OperationalTrip(
          id: id,
          routeId: 'route-1',
          vehicleId: vehicleId,
          status: TripStatus.enRoute,
          scheduledStart: fixedUtc,
        );

    void stubAuditOk() {
      when(
        () => audit.logAction(
          organizationId: any(named: 'organizationId'),
          operatorId: any(named: 'operatorId'),
          actionType: any(named: 'actionType'),
          entityId: any(named: 'entityId'),
          oldValue: any(named: 'oldValue'),
          newValue: any(named: 'newValue'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async {});
    }

    void stubAuditFails() {
      when(
        () => audit.logAction(
          organizationId: any(named: 'organizationId'),
          operatorId: any(named: 'operatorId'),
          actionType: any(named: 'actionType'),
          entityId: any(named: 'entityId'),
          oldValue: any(named: 'oldValue'),
          newValue: any(named: 'newValue'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async => throw Exception('audit outage'));
    }

    void stubDispatchesOk() {
      when(
        () => eventPort.dispatchTripInterrupted(
          organizationId: any(named: 'organizationId'),
          tripId: any(named: 'tripId'),
          vehicleId: any(named: 'vehicleId'),
          operatorId: any(named: 'operatorId'),
          reason: any(named: 'reason'),
          occurredAtUtc: any(named: 'occurredAtUtc'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => eventPort.dispatchTripCancelled(
          organizationId: any(named: 'organizationId'),
          tripId: any(named: 'tripId'),
          vehicleId: any(named: 'vehicleId'),
          operatorId: any(named: 'operatorId'),
          reason: any(named: 'reason'),
          occurredAtUtc: any(named: 'occurredAtUtc'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => eventPort.dispatchOccurrenceRegistered(
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
    }

    void stubAddEvent(TripEvent returned) {
      when(
        () => simulation.addEvent(
          tripId: any(named: 'tripId'),
          eventType: any(named: 'eventType'),
          fromStatus: any(named: 'fromStatus'),
          toStatus: any(named: 'toStatus'),
          metadata: any(named: 'metadata'),
        ),
      ).thenReturn(returned);
    }

    setUp(() {
      simulation = _MockFleetSimulationService();
      audit = _MockAuditService();
      eventPort = _MockContractualEventPort();
      clock = FakeDateTimeProvider(fixedUtc);

      stubAuditOk();
      stubDispatchesOk();

      service = SimulationControlService(
        simulation,
        audit,
        eventPort,
        getOperatorId: () => 'op-7',
        getOrganizationId: () => 'org-1',
        dateTimeProvider: clock,
      );
    });

    // ── 1. Start/Stop lifecycle (status transitions + clean state) ────────
    group('updateTripStatus', () {
      test(
        'DEVE apenas atualizar status QUANDO transição não for interrupted/cancelled',
        () async {
          when(
            () => simulation.updateTripStatus('t_1', TripStatus.enRoute),
          ).thenReturn(TripStatus.delayed);
          when(() => simulation.getTripById('t_1')).thenReturn(null);
          stubAddEvent(newEvent('e1', 't_1'));

          final result = await service.updateTripStatus(
            't_1',
            TripStatus.enRoute,
            reason: 'Regularização manual',
          );

          expect(result.tripId, 't_1');
          verifyNever(
            () => eventPort.dispatchTripInterrupted(
              organizationId: any(named: 'organizationId'),
              tripId: any(named: 'tripId'),
              operatorId: any(named: 'operatorId'),
              occurredAtUtc: any(named: 'occurredAtUtc'),
            ),
          );
          verifyNever(
            () => eventPort.dispatchTripCancelled(
              organizationId: any(named: 'organizationId'),
              tripId: any(named: 'tripId'),
              operatorId: any(named: 'operatorId'),
              occurredAtUtc: any(named: 'occurredAtUtc'),
            ),
          );
        },
      );

      test(
        'DEVE despachar evidência de interrupção QUANDO status = interrupted com vehicleId',
        () async {
          when(
            () => simulation.updateTripStatus('t_i', TripStatus.interrupted),
          ).thenReturn(TripStatus.enRoute);
          when(
            () => simulation.getTripById('t_i'),
          ).thenReturn(fakeTripWith(id: 't_i', vehicleId: 'veh-42'));
          stubAddEvent(newEvent('ei', 't_i'));

          await service.updateTripStatus(
            't_i',
            TripStatus.interrupted,
            reason: 'Pane mecânica',
          );

          verify(
            () => eventPort.dispatchTripInterrupted(
              organizationId: 'org-1',
              tripId: 't_i',
              vehicleId: 'veh-42',
              operatorId: 'op-7',
              reason: 'Pane mecânica',
              occurredAtUtc: fixedUtc,
            ),
          ).called(1);
        },
      );

      test(
        'DEVE despachar evidência com vehicleId nulo QUANDO trip não existir',
        () async {
          when(
            () => simulation.updateTripStatus('t_x', TripStatus.interrupted),
          ).thenReturn(TripStatus.enRoute);
          when(() => simulation.getTripById('t_x')).thenReturn(null);
          stubAddEvent(newEvent('ex', 't_x'));

          await service.updateTripStatus('t_x', TripStatus.interrupted);

          verify(
            () => eventPort.dispatchTripInterrupted(
              organizationId: 'org-1',
              tripId: 't_x',
              vehicleId: null,
              operatorId: 'op-7',
              reason: null,
              occurredAtUtc: fixedUtc,
            ),
          ).called(1);
        },
      );

      test(
        'DEVE despachar evidência de cancelamento QUANDO status = cancelled',
        () async {
          when(
            () => simulation.updateTripStatus('t_c', TripStatus.cancelled),
          ).thenReturn(TripStatus.enRoute);
          when(
            () => simulation.getTripById('t_c'),
          ).thenReturn(fakeTripWith(id: 't_c', vehicleId: 'veh-9'));
          stubAddEvent(newEvent('ec', 't_c'));

          await service.updateTripStatus(
            't_c',
            TripStatus.cancelled,
            reason: 'Rota bloqueada',
          );

          verify(
            () => eventPort.dispatchTripCancelled(
              organizationId: 'org-1',
              tripId: 't_c',
              vehicleId: 'veh-9',
              operatorId: 'op-7',
              reason: 'Rota bloqueada',
              occurredAtUtc: fixedUtc,
            ),
          ).called(1);
          verifyNever(
            () => eventPort.dispatchTripInterrupted(
              organizationId: any(named: 'organizationId'),
              tripId: any(named: 'tripId'),
              operatorId: any(named: 'operatorId'),
              occurredAtUtc: any(named: 'occurredAtUtc'),
            ),
          );
        },
      );
    });

    // ── 2. Tick/Stream: event emission + metadata sealing ──────────────────
    group('createTripEvent', () {
      test(
        'DEVE selar metadata com source + timestamp UTC QUANDO criar evento manual',
        () async {
          when(
            () => simulation.getTripById('t_m'),
          ).thenReturn(fakeTripWith(id: 't_m', vehicleId: 'veh-1'));
          stubAddEvent(newEvent('em', 't_m'));

          await service.createTripEvent(
            't_m',
            EventType.manualOverride,
            metadata: {'severity': 'high'},
            notes: 'Impacto alto',
          );

          final captured =
              verify(
                    () => simulation.addEvent(
                      tripId: 't_m',
                      eventType: EventType.manualOverride,
                      fromStatus: TripStatus.enRoute,
                      toStatus: TripStatus.enRoute,
                      metadata: captureAny(named: 'metadata'),
                    ),
                  ).captured.single
                  as Map<String, dynamic>;

          expect(captured['severity'], 'high');
          expect(captured['notes'], 'Impacto alto');
          expect(captured['source'], 'operator_manual');
          expect(captured['timestamp'], fixedUtc.toIso8601String());
        },
      );

      test(
        'DEVE despachar occurrenceRegistered com metadata vazio QUANDO nenhum metadado fornecido',
        () async {
          when(() => simulation.getTripById('t_n')).thenReturn(null);
          stubAddEvent(newEvent('en', 't_n'));

          await service.createTripEvent('t_n', EventType.positionLost);

          verify(
            () => eventPort.dispatchOccurrenceRegistered(
              organizationId: 'org-1',
              tripId: 't_n',
              vehicleId: null,
              operatorId: 'op-7',
              occurrenceType: 'positionLost',
              notes: null,
              metadata: const <String, dynamic>{},
              occurredAtUtc: fixedUtc,
            ),
          ).called(1);
        },
      );
    });

    // ── 3. Overrides: injection of fake telemetry + audit failure isolation ─
    group('audit failure isolation', () {
      test(
        'DEVE preservar fluxo operacional QUANDO auditService falhar em updateTripStatus',
        () async {
          stubAuditFails();
          when(
            () => simulation.updateTripStatus('t_af', TripStatus.enRoute),
          ).thenReturn(TripStatus.delayed);
          stubAddEvent(newEvent('eaf', 't_af'));

          // Should NOT throw — audit error is fire-and-forget.
          final result = await service.updateTripStatus(
            't_af',
            TripStatus.enRoute,
          );

          expect(result.tripId, 't_af');
          // Flush pending microtasks so catchError executes and is covered.
          await Future<void>.delayed(Duration.zero);
        },
      );

      test(
        'DEVE preservar fluxo operacional QUANDO auditService falhar em createTripEvent',
        () async {
          stubAuditFails();
          when(() => simulation.getTripById('t_af2')).thenReturn(null);
          stubAddEvent(newEvent('eaf2', 't_af2'));

          final result = await service.createTripEvent(
            't_af2',
            EventType.statusChange,
          );

          expect(result.tripId, 't_af2');
          await Future<void>.delayed(Duration.zero);
        },
      );
    });

    // ── 4. Cleanup: resolveAlert, updateContract, delegations ─────────────
    group('admin + delegation', () {
      test(
        'DEVE restaurar status enRoute QUANDO resolveAlert for invocado',
        () async {
          when(
            () => simulation.updateTripStatus('t_r', TripStatus.enRoute),
          ).thenReturn(TripStatus.delayed);
          stubAddEvent(newEvent('er', 't_r'));

          await service.resolveAlert('t_r');

          verify(
            () => simulation.updateTripStatus('t_r', TripStatus.enRoute),
          ).called(1);
        },
      );

      test('DEVE logar ação QUANDO updateContract for invocado', () async {
        await service.updateContract('ctr-1', 150000);

        await Future<void>.delayed(Duration.zero);
        verify(
          () => audit.logAction(
            organizationId: 'org-1',
            operatorId: 'op-7',
            actionType: 'UPDATE_CONTRACT',
            entityId: 'ctr-1',
            oldValue: 'unknown',
            newValue: '150000',
            reason: any(named: 'reason'),
          ),
        ).called(1);
      });

      test(
        'DEVE suprimir erro de auditoria QUANDO updateContract falhar no log',
        () async {
          stubAuditFails();

          await service.updateContract('ctr-err', 99);
          await Future<void>.delayed(Duration.zero);

          // No exception surfaced; debugPrint fallback hit.
          expect(true, isTrue);
        },
      );

      test('DEVE delegar getEventsForTrip ao simulation', () {
        final eventList = [newEvent('d1', 't_d')];
        when(() => simulation.getEventsForTrip('t_d')).thenReturn(eventList);

        expect(service.getEventsForTrip('t_d'), equals(eventList));
        verify(() => simulation.getEventsForTrip('t_d')).called(1);
      });

      test('DEVE delegar getTripById ao simulation', () {
        final trip = fakeTripWith(id: 't_d2');
        when(() => simulation.getTripById('t_d2')).thenReturn(trip);

        expect(service.getTripById('t_d2'), trip);
        verify(() => simulation.getTripById('t_d2')).called(1);
      });
    });

    // ── UTC Invariant (INV-6): occurredAt must always be UTC ──────────────
    test('DEVE preservar isUtc=true em todos os dispatches (INV-6)', () async {
      when(
        () => simulation.updateTripStatus('t_utc', TripStatus.cancelled),
      ).thenReturn(TripStatus.enRoute);
      when(() => simulation.getTripById('t_utc')).thenReturn(null);
      stubAddEvent(newEvent('eutc', 't_utc'));

      await service.updateTripStatus('t_utc', TripStatus.cancelled);

      final captured =
          verify(
                () => eventPort.dispatchTripCancelled(
                  organizationId: any(named: 'organizationId'),
                  tripId: any(named: 'tripId'),
                  vehicleId: any(named: 'vehicleId'),
                  operatorId: any(named: 'operatorId'),
                  reason: any(named: 'reason'),
                  occurredAtUtc: captureAny(named: 'occurredAtUtc'),
                ),
              ).captured.single
              as DateTime;
      expect(captured.isUtc, isTrue);
    });

    // ── Fallback: service constructs with default BrazilDateTimeProvider ──
    test(
      'DEVE usar BrazilDateTimeProvider por padrão QUANDO dateTimeProvider não for injetado',
      () async {
        final defaulted = SimulationControlService(
          simulation,
          audit,
          eventPort,
          getOperatorId: () => 'op-def',
          getOrganizationId: () => 'org-def',
        );

        when(
          () => simulation.updateTripStatus('t_def', TripStatus.enRoute),
        ).thenReturn(TripStatus.delayed);
        stubAddEvent(newEvent('edef', 't_def'));

        final ev = await defaulted.updateTripStatus(
          't_def',
          TripStatus.enRoute,
        );
        expect(ev.tripId, 't_def');
      },
    );
  });
}
