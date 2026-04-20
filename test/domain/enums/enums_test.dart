import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';

void main() {
  group('Enums Domain Tests', () {
    test('MotionState extension methods', () {
      expect(MotionState.moving.label, 'Em Movimento');
      expect(MotionState.stopped.label, 'Parado');
      expect(MotionState.dwellingAtStop.label, 'No Ponto');
      expect(MotionState.slowTraffic.label, 'Trânsito Lento');
    });

    test('ConnectivityState extension methods', () {
      expect(ConnectivityState.healthy.label, 'Sinal OK');
      expect(ConnectivityState.signalLost.label, 'Sem Sinal');
    });

    test('RouteAdherence extension methods', () {
      expect(RouteAdherence.onRoute.label, 'Na Rota');
      expect(RouteAdherence.offRoute.label, 'Fora da Rota');
    });

    test('TripStatus parsing and logic', () {
      expect(TripStatus.fromString('scheduled'), TripStatus.scheduled);
      expect(TripStatus.fromString('en_route'), TripStatus.enRoute);
      expect(TripStatus.fromString('completed'), TripStatus.completed);
      expect(TripStatus.fromString('cancelled'), TripStatus.cancelled);
      expect(
        TripStatus.fromString('invalid'),
        TripStatus.scheduled,
      ); // Default fallback

      expect(TripStatus.enRoute.isActive, isTrue);
      expect(TripStatus.detour.isActive, isTrue);
      expect(TripStatus.completed.isActive, isFalse);

      expect(TripStatus.completed.isTerminal, isTrue);
      expect(TripStatus.cancelled.isTerminal, isTrue);
      expect(TripStatus.enRoute.isTerminal, isFalse);

      expect(
        TripStatus.detour.requiresAttention,
        isFalse,
      ); // handled separately or naturally false
      expect(TripStatus.enRoute.requiresAttention, isFalse);
    });

    group('EventType', () {
      test('label returns correct Portuguese strings', () {
        expect(EventType.statusChange.label, 'Mudança de Status');
        expect(EventType.delayDetected.label, 'Atraso Detectado');
        expect(EventType.delayRecovered.label, 'Atraso Recuperado');
        expect(EventType.positionLost.label, 'Posição Perdida');
        expect(EventType.positionRestored.label, 'Posição Restaurada');
        expect(EventType.driverAssigned.label, 'Motorista Alocado');
        expect(EventType.vehicleAssigned.label, 'Veículo Alocado');
        expect(EventType.feedDisconnected.label, 'Feed Desconectado');
        expect(EventType.feedReconnected.label, 'Feed Reconectado');
        expect(EventType.manualOverride.label, 'Alteração Manual');
      });

      test('severity groups warning events correctly', () {
        expect(EventType.delayDetected.severity, EventSeverity.warning);
        expect(EventType.positionLost.severity, EventSeverity.warning);
        expect(EventType.feedDisconnected.severity, EventSeverity.warning);
      });

      test('severity groups info events correctly', () {
        expect(EventType.delayRecovered.severity, EventSeverity.info);
        expect(EventType.positionRestored.severity, EventSeverity.info);
        expect(EventType.feedReconnected.severity, EventSeverity.info);
      });

      test('severity groups neutral events correctly', () {
        expect(EventType.statusChange.severity, EventSeverity.neutral);
        expect(EventType.driverAssigned.severity, EventSeverity.neutral);
        expect(EventType.vehicleAssigned.severity, EventSeverity.neutral);
        expect(EventType.manualOverride.severity, EventSeverity.neutral);
      });

      test('fromString parses all snake_case values', () {
        expect(EventType.fromString('status_change'), EventType.statusChange);
        expect(EventType.fromString('delay_detected'), EventType.delayDetected);
        expect(
          EventType.fromString('delay_recovered'),
          EventType.delayRecovered,
        );
        expect(EventType.fromString('position_lost'), EventType.positionLost);
        expect(
          EventType.fromString('position_restored'),
          EventType.positionRestored,
        );
        expect(
          EventType.fromString('driver_assigned'),
          EventType.driverAssigned,
        );
        expect(
          EventType.fromString('vehicle_assigned'),
          EventType.vehicleAssigned,
        );
        expect(
          EventType.fromString('feed_disconnected'),
          EventType.feedDisconnected,
        );
        expect(
          EventType.fromString('feed_reconnected'),
          EventType.feedReconnected,
        );
        expect(
          EventType.fromString('manual_override'),
          EventType.manualOverride,
        );
      });

      test('fromString returns statusChange for unknown value', () {
        expect(EventType.fromString('unknown_xyz'), EventType.statusChange);
      });

      test('dbValue converts camelCase to snake_case', () {
        expect(EventType.statusChange.dbValue, 'status_change');
        expect(EventType.delayDetected.dbValue, 'delay_detected');
        expect(EventType.manualOverride.dbValue, 'manual_override');
        expect(EventType.feedReconnected.dbValue, 'feed_reconnected');
      });
    });

    group('VehicleStatus', () {
      test('label returns correct Portuguese strings', () {
        expect(VehicleStatus.available.label, 'Disponível');
        expect(VehicleStatus.inService.label, 'Em Serviço');
        expect(VehicleStatus.maintenance.label, 'Manutenção');
        expect(VehicleStatus.retired.label, 'Aposentado');
      });

      test('fromString parses all values', () {
        expect(VehicleStatus.fromString('available'), VehicleStatus.available);
        expect(VehicleStatus.fromString('in_service'), VehicleStatus.inService);
        expect(
          VehicleStatus.fromString('maintenance'),
          VehicleStatus.maintenance,
        );
        expect(VehicleStatus.fromString('retired'), VehicleStatus.retired);
        expect(VehicleStatus.fromString('unknown'), VehicleStatus.available);
      });

      test('dbValue returns correct db values', () {
        expect(VehicleStatus.inService.dbValue, 'in_service');
        expect(VehicleStatus.available.dbValue, 'available');
        expect(VehicleStatus.maintenance.dbValue, 'maintenance');
        expect(VehicleStatus.retired.dbValue, 'retired');
      });
    });
  });
}
