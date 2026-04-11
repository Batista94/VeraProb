import 'package:veraprob/domain/enums/user_role.dart';

class DeleteContractorCommand {
  final String organizationId;
  final UserRole callerRole;
  final String contractorId;

  /// Session ID for tenant validation.
  final String sessionId;

  const DeleteContractorCommand({
    required this.organizationId,
    required this.callerRole,
    required this.contractorId,
    required this.sessionId,
  });
}
