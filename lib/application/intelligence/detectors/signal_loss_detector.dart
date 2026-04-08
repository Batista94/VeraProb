import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/entities/operational_warning.dart';
import 'package:veraprob/domain/entities/trip_event.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'situation_detector.dart';

/// Detects if a vehicle has lost GPS transmission connectivity.
///
/// Rule:
/// - If [ConnectivityState] from the Normalization Layer is [ConnectivityState.signalLost],
///   we flag it to alert the operator.
class SignalLossDetector extends SituationDetector {
  const SignalLossDetector(super.dateTimeProvider)
    : super(id: 'signal_loss', name: 'Detector de Perda de Sinal');

  @override
  bool canDetect(OperationalTrip trip) {
    return trip.isActive;
  }

  @override
  OperationalWarning? evaluate(
    OperationalTrip trip,
    VehicleOperationalState? state,
    List<TripEvent> history,
  ) {
    if (state == null) return null;

    if (state.connectivityState == ConnectivityState.signalLost) {
      final secondsSincePing = dateTimeProvider
          .now()
          .difference(state.lastRawPingAt)
          .inSeconds;

      return OperationalWarning(
        id: 'warn_signal_lost_${trip.id}',
        type: 'signal_lost',
        message: 'Perda de Sinal GPS: >${secondsSincePing}s',
        severityScore: 40, // High severity
        detectedAt: dateTimeProvider.now(),
        metadata: {
          'last_ping_at': state.lastRawPingAt.toIso8601String(),
          'seconds_offline': secondsSincePing,
        },
      );
    }

    return null;
  }
}
