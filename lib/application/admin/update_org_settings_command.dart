import '../../domain/enums/user_role.dart';

class UpdateOrgSettingsCommand {
  final String organizationId;
  final UserRole callerRole;
  final String name;
  final String timezone;
  final String currencyCode;
  final String? logoUrl;

  const UpdateOrgSettingsCommand({
    required this.organizationId,
    required this.callerRole,
    required this.name,
    required this.timezone,
    required this.currencyCode,
    this.logoUrl,
  });
}
