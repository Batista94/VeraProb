import 'package:veraprob/domain/admin/actor_type.dart';

/// Service interface for logging governance changes to system_audit_log.
///
/// Separate from [AuditService] which handles tenant-scoped operational audit logs.
/// This service handles cross-tenant system-level governance events.
abstract class SystemAuditLogService {
  /// Log a governance change with before/after snapshots.
  ///
  /// [eventType] must be one of: QUOTA_CHANGE, STATUS_CHANGE, LIMIT_CHANGE,
  /// SECRET_ROTATION, IMPERSONATION_START, IMPERSONATION_REVOKE,
  /// OPERATIONAL_PARAM_CHANGE.
  ///
  /// [reason] is mandatory for governance events (enforced by DB trigger).
  Future<void> logGovernanceChange({
    required String eventType,
    required String reason,
    required ActorType actorType,
    String? impersonatorId,
    required String organizationId,
    String? organizationName,
    required Map<String, Object?> oldSnapshot,
    required Map<String, Object?> newSnapshot,
    String? source,
  });
}
