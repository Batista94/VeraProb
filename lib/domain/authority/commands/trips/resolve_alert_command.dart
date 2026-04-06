import 'package:veraprob/domain/authority/commands/operational_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';

/// Command to manually resolve an active alert on a specific Trip.
class ResolveAlertCommand extends OperationalCommand {
  final String tripId;

  const ResolveAlertCommand({required this.tripId});

  @override
  TargetRef get targetRef => TargetRef('trip', tripId);

  @override
  List<Object?> get props => [tripId];
}
