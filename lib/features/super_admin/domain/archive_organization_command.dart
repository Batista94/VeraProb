// pr_scanner: ignore-regression
import 'package:veraprob/domain/admin/org_status.dart';

/// Immutable command DTO for archiving an existing tenant organization.
///
/// INV-4: Pure Dart — zero infrastructure dependencies.
class ArchiveOrganizationCommand {
  final String orgId;
  final String reason;
  final String superAdminUserId;
  final String sessionId;

  /// Current status of the org — used by the handler for guard checks
  /// before the network round-trip (fail-fast, INV-10).
  final OrgStatus currentStatus;

  const ArchiveOrganizationCommand({
    required this.orgId,
    required this.reason,
    required this.superAdminUserId,
    required this.currentStatus,
    required this.sessionId,
  });
}
