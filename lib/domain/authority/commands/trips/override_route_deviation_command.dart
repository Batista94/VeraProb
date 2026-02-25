import '../operational_command.dart';
import '../../core/authority_types.dart';

/// Command to explicitly authorize or deny a vehicle to deviate from the planned route.
class OverrideRouteDeviationCommand extends OperationalCommand {
  final String tripId;
  final bool isAuthorized;
  final String? reason;

  const OverrideRouteDeviationCommand({
    required this.tripId,
    required this.isAuthorized,
    this.reason,
  });

  @override
  TargetRef get targetRef => TargetRef('trip', tripId);

  @override
  List<Object?> get props => [tripId, isAuthorized, reason];
}
