import 'package:veraprob/domain/authority/commands/operational_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';

/// Command to formally acknowledge an active alert without resolving it.
/// Indicates that an operator is aware and investigating.
class AcknowledgeAlertCommand extends OperationalCommand {
  final String tripId;

  @override
  final String? targetOrganizationId;

  const AcknowledgeAlertCommand({
    required this.tripId,
    this.targetOrganizationId,
  });

  @override
  TargetRef get targetRef => TargetRef('trip', tripId);

  @override
  List<Object?> get props => [tripId, targetOrganizationId];
}
