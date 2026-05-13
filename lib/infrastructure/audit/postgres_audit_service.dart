import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/application/audit/audit_service.dart';
import 'package:veraprob/domain/entities/audit_log.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

/// Postgres implementation of the [AuditService].
/// Operates strictly as an append-only persistence adapter.
class PostgresAuditService implements AuditService {
  final SupabaseClient _client;
  final IDateTimeProvider _dateTimeProvider;

  PostgresAuditService(this._client, this._dateTimeProvider);

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
      id: const Uuid()
          .v4(), // Managed by client to ensure ledger integrity before insertion
      organizationId: organizationId,
      operatorId: operatorId,
      actionType: actionType,
      entityId: entityId,
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
      timestamp: _dateTimeProvider.nowUtc(),
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
            operatorId: (data['operator_id'] as String?) ?? '',
            actionType: (data['type'] as String?) ?? '',
            entityId: (data['set_id'] as String?) ?? '',
            timestamp: DateTime.parse(data['occurred_at_utc']).toUtc(),
          ),
        )
        .toList();
  }
}
