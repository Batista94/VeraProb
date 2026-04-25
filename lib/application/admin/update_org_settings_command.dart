import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class UpdateOrgSettingsCommand {
  final String organizationId;
  final UserRole callerRole;
  final String? name;
  final String? timezone;
  final String? currencyCode;
  final String? logoUrl;
  final String? organizationType;
  final OrgCapabilities? capabilities;

  /// Session ID for tenant validation.
  final String sessionId;

  const UpdateOrgSettingsCommand({
    required this.organizationId,
    required this.callerRole,
    this.name,
    this.timezone,
    this.currencyCode,
    this.logoUrl,
    this.organizationType,
    this.capabilities,
    required this.sessionId,
  });
}
