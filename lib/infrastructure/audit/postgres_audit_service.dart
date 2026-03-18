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
    required String organizationId,
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
      organizationId: organizationId,
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
  Future<List<AuditLog>> getLogsForEntity(String entityId) async {
    final response = await _client
        .from('audit_logs')
        .select()
        .eq('entity_id', entityId)
        .order('timestamp', ascending: false);

    return (response as List).map((data) => AuditLog.fromJson(data)).toList();
  }

  @override
  Future<List<AuditLog>> getRecentLogs({int limit = 50}) async {
    final response = await _client
        .from('sla_audit_ledger_v2')
        .select()
        .order('occurred_at_utc', ascending: false)
        .limit(limit);

    return (response as List)
        .map(
          (data) => AuditLog(
            id: data['id'],
            organizationId: data['organization_id'],
            operatorId: data['operator_id'] ?? '',
            actionType: data['event_type'],
            entityId:
                data['entity_id'] ?? data['contract_id'] ?? '', // Handle both
            timestamp: DateTime.parse(data['occurred_at_utc']),
          ),
        )
        .toList();
  }
}
