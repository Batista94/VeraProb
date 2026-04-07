import 'package:veraprob/domain/authority/commands/operational_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

/// Command to manually override the status of a Trip.
class UpdateTripStatusCommand extends OperationalCommand {
  final String tripId;
  final TripStatus newStatus;
  final String? reason;

  @override
  final String? targetOrganizationId;

  const UpdateTripStatusCommand({
    required this.tripId,
    required this.newStatus,
    this.reason,
    this.targetOrganizationId,
  });

  @override
  TargetRef get targetRef => TargetRef('trip', tripId);

  @override
  List<Object?> get props => [tripId, newStatus, reason, targetOrganizationId];
}
