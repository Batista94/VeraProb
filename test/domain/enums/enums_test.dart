import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/enums/motion_state.dart';
import 'package:busflow/domain/enums/connectivity_state.dart';
import 'package:busflow/domain/enums/route_adherence.dart';
import 'package:busflow/domain/enums/trip_status.dart';

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
  });
}
