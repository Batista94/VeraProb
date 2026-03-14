import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/audit_log.dart';
import '../../core/services/logger_service.dart';
import '../../infrastructure/audit/postgres_audit_service.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';

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

/// In-memory implementation of the AuditService for Sprint 6.
/// This logs accurately to the ephemeral store and the Debug console,
/// paving the way for the Supabase implementation in the future.
class InMemoryAuditService implements AuditService {
  final List<AuditLog> _logs = [];
  final LoggerService _logger = LoggerService();

  @override
  Future<void> logAction({
    required String organizationId,
    required String operatorId,
    required String actionType,
    required String entityId,
    String? oldValue,
    String? newValue,
    String? reason,
  }) async {
    final log = AuditLog(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // ephemeral mock id
      organizationId: organizationId,
      operatorId: operatorId,
      actionType: actionType,
      entityId: entityId,
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
      timestamp: DateTime.now().toUtc(),
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
  Future<List<AuditLog>> getLogsForEntity(String entityId) async {
    return _logs.where((log) => log.entityId == entityId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Latest first
  }

  @override
  Future<List<AuditLog>> getRecentLogs({int limit = 50}) async {
    final sorted = List<AuditLog>.from(_logs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final auditServiceProvider = Provider<AuditService>((ref) {
  final mode = ref.watch(persistenceModeProvider);

  switch (mode) {
    case PersistenceMode.inMemory:
      return InMemoryAuditService();
    case PersistenceMode.postgres:
      final client = ref.watch(supabaseClientProvider);
      return PostgresAuditService(client);
  }
});
