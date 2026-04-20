import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/application/normalization/models/trip_status_view.dart';

void main() {
  group('Normalization Models Coverage', () {
    test('MotionState.label and isStationary', () {
      expect(MotionState.moving.label, 'Em Movimento');
      expect(MotionState.slowTraffic.label, 'Trânsito Lento');
      expect(MotionState.stopped.label, 'Parado');
      expect(MotionState.dwellingAtStop.label, 'No Ponto');

      expect(MotionState.moving.isStationary, false);
      expect(MotionState.slowTraffic.isStationary, false);
      expect(MotionState.stopped.isStationary, true);
      expect(MotionState.dwellingAtStop.isStationary, true);
    });

    test('RouteAdherence.label and requiresAttention', () {
      expect(RouteAdherence.onRoute.label, 'Na Rota');
      expect(RouteAdherence.minorDeviation.label, 'Desvio Leve');
      expect(RouteAdherence.offRoute.label, 'Fora da Rota');

      expect(RouteAdherence.onRoute.requiresAttention, false);
      expect(RouteAdherence.minorDeviation.requiresAttention, false);
      expect(RouteAdherence.offRoute.requiresAttention, true);
    });

    test('TripStatusView.label and isActive', () {
      expect(TripStatusView.scheduled.label, 'PROGRAMADO');
      expect(TripStatusView.enRoute.label, 'EM ROTA');
      expect(TripStatusView.delayed.label, 'ATRASADO');
      expect(TripStatusView.atStop.label, 'NO PONTO');
      expect(TripStatusView.interrupted.label, 'INTERROMPIDO');
      expect(TripStatusView.noShow.label, 'NO-SHOW');
      expect(TripStatusView.maintenance.label, 'MANUTENÇÃO');
      expect(TripStatusView.completed.label, 'CONCLUÍDO');
      expect(TripStatusView.cancelled.label, 'CANCELADO');

      expect(TripStatusView.scheduled.isActive, true);
      expect(TripStatusView.enRoute.isActive, true);
      expect(TripStatusView.delayed.isActive, true);
      expect(TripStatusView.atStop.isActive, true);
      expect(TripStatusView.interrupted.isActive, true);

      expect(TripStatusView.noShow.isActive, false);
      expect(TripStatusView.maintenance.isActive, false);
      expect(TripStatusView.completed.isActive, false);
      expect(TripStatusView.cancelled.isActive, false);
    });
  });
}
