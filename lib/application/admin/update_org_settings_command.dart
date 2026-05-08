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

  /// Mandatory justification for governance changes (capabilities, status, plan_type).
  final String? reason;

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
    this.reason,
    required this.sessionId,
  });
}
