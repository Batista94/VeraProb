import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/enums/user_role.dart';

/// Command to record an off-band ("De Acordo interno") sanction acceptance —
/// e.g. the carrier agreed by email/phone and a TENANT_ADMIN documents it.
class AcknowledgeSanctionInternalCommand extends Equatable {
  final String organizationId;
  final String queueEntryId;
  final String acknowledgedByUserId;
  final String? notes;
  final UserRole callerRole;
  final String sessionId;

  const AcknowledgeSanctionInternalCommand({
    required this.organizationId,
    required this.queueEntryId,
    required this.acknowledgedByUserId,
    required this.callerRole,
    required this.sessionId,
    this.notes,
  });

  @override
  List<Object?> get props => [
    organizationId,
    queueEntryId,
    acknowledgedByUserId,
    notes,
    callerRole,
    sessionId,
  ];
}
