import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/entities/operational_warning.dart';
import 'package:veraprob/domain/entities/trip_event.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';

/// Base interface for all situation detectors.
///
/// A detector is a pure function that analyzes a trip and its history
/// to emit an [OperationalWarning] if an anomaly is detected.
abstract class SituationDetector {
  final String id;
  final String name;
  final IDateTimeProvider dateTimeProvider;

  const SituationDetector(
    this.dateTimeProvider, {
    required this.id,
    required this.name,
  });

  /// Check if this detector applies to the current trip state.
  bool canDetect(OperationalTrip trip);

  /// Evaluate the trip and return a warning if an issue is found.
  OperationalWarning? evaluate(
    OperationalTrip trip,
    VehicleOperationalState? state,
    List<TripEvent> history,
  );
}
