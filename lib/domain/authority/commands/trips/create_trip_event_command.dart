import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/authority/commands/operational_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';

/// Command to register an operational occurrence on a specific Trip.
class CreateTripEventCommand extends OperationalCommand {
  final String tripId;
  final EventType type;
  final Map<String, dynamic>? metadata;
  final String? notes;

  @override
  final String? targetOrganizationId;

  const CreateTripEventCommand({
    required this.tripId,
    required this.type,
    this.metadata,
    this.notes,
    this.targetOrganizationId,
  });

  @override
  TargetRef get targetRef => TargetRef('trip', tripId);

  @override
  List<Object?> get props => [
    tripId,
    type,
    metadata,
    notes,
    targetOrganizationId,
  ];
}
