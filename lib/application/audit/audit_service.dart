import 'package:veraprob/domain/entities/audit_log.dart';

/// Interface for the Audit subsystem.
abstract class AuditService {
  /// Records a new action log securely.
  Future<void> logAction({
    required String organizationId,
    required String operatorId,
    required String actionType,
    required String entityId,
    String? oldValue,
    String? newValue,
    String? reason,
  });

  /// Retrieves chronological audit logs for a specific entity.
  Future<List<AuditLog>> getLogsForEntity(String entityId);

  /// Retrieves the most recent system-wide actions (useful for Admin dashboards).
  Future<List<AuditLog>> getRecentLogs({int limit = 50});
}
