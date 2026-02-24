import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/audit_log.dart';
import '../../core/services/logger_service.dart';

/// Interface for the Audit subsystem.
abstract class AuditService {
  /// Records a new action log securely.
  Future<void> logAction({
    required String operatorId,
    required String actionType,
    required String entityId,
    String? oldValue,
    String? newValue,
    String? reason,
  });

  /// Retrieves chronological audit logs for a specific entity.
  List<AuditLog> getLogsForEntity(String entityId);

  /// Retrieves the most recent system-wide actions (useful for Admin dashboards).
  List<AuditLog> getRecentLogs({int limit = 50});
}

/// In-memory implementation of the AuditService for Sprint 6.
/// This logs accurately to the ephemeral store and the Debug console,
/// paving the way for the Supabase implementation in the future.
class InMemoryAuditService implements AuditService {
  final List<AuditLog> _logs = [];
  final LoggerService _logger = LoggerService();

  @override
  Future<void> logAction({
    required String operatorId,
    required String actionType,
    required String entityId,
    String? oldValue,
    String? newValue,
    String? reason,
  }) async {
    final log = AuditLog(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // ephemeral mock id
      operatorId: operatorId,
      actionType: actionType,
      entityId: entityId,
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
      timestamp: DateTime.now(),
    );

    _logs.add(log);

    // Also print to console so we can trace it during manual validation
    _logger.log(
      '[AUDIT] Action: $actionType by Operator: $operatorId on Entity: $entityId. '
      'From: $oldValue -> To: $newValue. Reason: $reason',
      component: 'Audit',
    );
  }

  @override
  List<AuditLog> getLogsForEntity(String entityId) {
    return _logs.where((log) => log.entityId == entityId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Latest first
  }

  @override
  List<AuditLog> getRecentLogs({int limit = 50}) {
    final sorted = List<AuditLog>.from(_logs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final auditServiceProvider = Provider<AuditService>((ref) {
  return InMemoryAuditService();
});
