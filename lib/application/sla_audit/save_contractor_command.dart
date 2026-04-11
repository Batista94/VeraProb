import 'package:veraprob/domain/enums/user_role.dart';

class SaveContractorCommand {
  final String organizationId;
  final UserRole callerRole;
  final String? id;
  final String name;
  final String? taxId;
  final String primaryEmail;
  final String contactName;

  /// Session ID for tenant validation.
  final String sessionId;

  const SaveContractorCommand({
    required this.organizationId,
    required this.callerRole,
    this.id,
    required this.name,
    this.taxId,
    required this.primaryEmail,
    required this.contactName,
    required this.sessionId,
  });
}
