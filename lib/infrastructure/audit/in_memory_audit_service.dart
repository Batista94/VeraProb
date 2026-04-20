import 'package:veraprob/application/audit/audit_service.dart';
import 'package:veraprob/core/services/logger_service.dart';
import 'package:veraprob/domain/entities/audit_log.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// In-memory implementation of the AuditService for Sprint 6.
/// This logs accurately to the ephemeral store and the Debug console,
/// paving the way for the Supabase implementation in the future.
class InMemoryAuditService implements AuditService {
  final List<AuditLog> _logs = [];
  final LoggerService _logger = LoggerService();
  final IDateTimeProvider _dateTimeProvider;

  InMemoryAuditService(this._dateTimeProvider);

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
      id: const Uuid().v4(), // Deterministic UUID v4 for ledger integrity
      organizationId: organizationId,
      operatorId: operatorId,
      actionType: actionType,
      entityId: entityId,
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
      timestamp: _dateTimeProvider.nowUtc(), // INV-9: UTC Mandatory
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
