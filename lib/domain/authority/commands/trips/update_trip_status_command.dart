import '../operational_command.dart';
import '../../core/authority_types.dart';
import '../../../enums/trip_status.dart';

/// Command to manually override the status of a Trip.
class UpdateTripStatusCommand extends OperationalCommand {
  final String tripId;
  final TripStatus newStatus;
  final String? reason;

  const UpdateTripStatusCommand({
    required this.tripId,
    required this.newStatus,
    this.reason,
  });

  @override
  TargetRef get targetRef => TargetRef('trip', tripId);

  @override
  List<Object?> get props => [tripId, newStatus, reason];
}
