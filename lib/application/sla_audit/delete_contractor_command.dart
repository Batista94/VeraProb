import '../../domain/enums/user_role.dart';

class DeleteContractorCommand {
  final String organizationId;
  final UserRole callerRole;
  final String contractorId;

  const DeleteContractorCommand({
    required this.organizationId,
    required this.callerRole,
    required this.contractorId,
  });
}
