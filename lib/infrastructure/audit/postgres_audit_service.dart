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

    return (response as List).map((data) {
      final payload = data['payload'] != null
          ? Map<String, dynamic>.from(data['payload'] as Map)
          : <String, dynamic>{};

      // Extract vehicle plate from payload
      String? vehiclePlate = payload['vehicle_plate'] as String?;
      if (vehiclePlate == null && payload['verdict_evidence'] != null) {
        final evidence = Map<String, dynamic>.from(
          payload['verdict_evidence'] as Map,
        );
        vehiclePlate = evidence['vehicle_plate'] as String?;
      }

      // Extract route name from payload
      String? routeName =
          payload['route_short_name'] as String? ??
          payload['route_name'] as String?;
      if (routeName == null && payload['verdict_evidence'] != null) {
        final evidence = Map<String, dynamic>.from(
          payload['verdict_evidence'] as Map,
        );
        routeName =
            evidence['route_short_name'] as String? ??
            evidence['route_name'] as String?;
      }

      // Extract reason/details from payload
      final String? reason =
          payload['reason'] as String? ??
          payload['rejection_reason'] as String? ??
          payload['resolution_reason'] as String?;

      return AuditLog(
        id: data['id'],
        organizationId: data['organization_id'],
        operatorId: (data['operator_id'] as String?) ?? '',
        actionType: (data['type'] as String?) ?? '',
        entityId: (data['set_id'] as String?) ?? '',
        timestamp: DateTime.parse(data['occurred_at_utc']).toUtc(),
        vehiclePlate: vehiclePlate,
        routeName: routeName,
        reason: reason,
      );
    }).toList();
  }
}
