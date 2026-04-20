import 'package:veraprob/domain/authority/commands/operational_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';

/// Command to dynamically swap the vehicle executing a trip mid-operation.
class ReassignVehicleCommand extends OperationalCommand {
  final String tripId;
  final String oldVehicleId;
  final String newVehicleId;
  final String? reason;

  @override
  final String? targetOrganizationId;

  const ReassignVehicleCommand({
    required this.tripId,
    required this.oldVehicleId,
    required this.newVehicleId,
    this.reason,
    this.targetOrganizationId,
  });

  @override
  // Here, the primary target of the action is the trip being modified.
  // The policy can check the command payload if vehicle-specific checks are needed.
  TargetRef get targetRef => TargetRef('trip', tripId);

  @override
  List<Object?> get props => [
    tripId,
    oldVehicleId,
    newVehicleId,
    reason,
    targetOrganizationId,
  ];
}
