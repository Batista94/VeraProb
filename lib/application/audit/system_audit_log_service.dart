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
    ActorType? actorType,
    String? impersonatorId,
    required String organizationId,
    String? organizationName,
    required Map<String, Object?> oldSnapshot,
    required Map<String, Object?> newSnapshot,

    /// Campos de contexto fixo exibidos no viewer mas excluídos do diff.
    /// Use para identificadores que não mudam (ex: email, user_id).
    Map<String, Object?>? context,
    String? source,
  });
}
