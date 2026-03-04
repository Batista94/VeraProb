import 'package:supabase_flutter/supabase_flutter.dart';
import '../../application/audit/audit_service.dart';
import '../../domain/entities/audit_log.dart';

/// Postgres implementation of the [AuditService].
/// Operates strictly as an append-only persistence adapter.
class PostgresAuditService implements AuditService {
  final SupabaseClient _client;

  PostgresAuditService(this._client);

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
      id: DateTime.now().millisecondsSinceEpoch
          .toString(), // Managed by DB or here
      operatorId: operatorId,
      actionType: actionType,
      entityId: entityId,
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
      timestamp: DateTime.now().toUtc(),
    );

    // Append-only persistence (fire and forget / await)
    await _client.from('audit_logs').insert(log.toJson());
  }

  @override
  List<AuditLog> getLogsForEntity(String entityId) {
    // The current public interface is synchronous, but Supabase is async.
    // Since Phase 2 rule strictly prohibits altering public contracts,
    // and runtime remains 100% InMemory, we throw here.
    throw UnimplementedError(
      'PostgresAuditService cannot implement synchronous read. Contract must be updated to Future.',
    );
  }

  @override
  List<AuditLog> getRecentLogs({int limit = 50}) {
    // Synchronous interface constraint.
    throw UnimplementedError(
      'PostgresAuditService cannot implement synchronous read. Contract must be updated to Future.',
    );
  }
}
