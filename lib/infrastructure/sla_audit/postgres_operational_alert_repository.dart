import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Postgres implementation of [OperationalAlertRepository] via Supabase.
class PostgresOperationalAlertRepository
    with PostgresErrorInterceptor
    implements OperationalAlertRepository {
  final SupabaseClient _client;

  PostgresOperationalAlertRepository(this._client);

  static const _table = 'operational_alerts';

  @override
  Future<String> save(OperationalAlert alert) async {
    try {
      final result = await _client
          .from(_table)
          .insert({
            'organization_id': alert.organizationId,
            'entity_id': alert.entityId,
            'contract_id': alert.contractId,
            'alert_type': alert.alertType,
            'severity': alert.severity,
            'triggered_at_utc': alert.triggeredAtUtc.toIso8601String(),
            'triggering_event_id': alert.triggeringEventId,
            'trace_id': alert.traceId,
            'context': alert.context,
            'status': alert.status,
          })
          .select('id')
          .single();
      return result['id'] as String;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'operational_alert');
    }
  }

  @override
  Future<List<OperationalAlert>> findActive(String organizationId) async {
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('organization_id', organizationId)
          .eq('status', 'ACTIVE')
          .order('severity')
          .order('triggered_at_utc', ascending: false);
      return data.map(_fromRow).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'operational_alert');
    }
  }

  @override
  Future<List<OperationalAlert>> findByEntityId(String entityId) async {
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('entity_id', entityId)
          .order('triggered_at_utc', ascending: false);
      return data.map(_fromRow).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'operational_alert');
    }
  }

  @override
  Future<OperationalAlert?> findById(String alertId) async {
    try {
      final data = await _client
          .from(_table)
          .select()
          .eq('id', alertId)
          .maybeSingle();
      return data == null ? null : _fromRow(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'operational_alert');
    }
  }

  @override
  Future<void> update(OperationalAlert alert) async {
    try {
      await _client
          .from(_table)
          .update({
            'status': alert.status,
            'acknowledged_at_utc': alert.acknowledgedAtUtc?.toIso8601String(),
            'acknowledged_by_user_id': alert.acknowledgedByUserId,
            'resolved_at_utc': alert.resolvedAtUtc?.toIso8601String(),
          })
          .eq('id', alert.id);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'operational_alert');
    }
  }

  @override
  Future<void> markViewed(String alertId, String userId) async {
    try {
      // Idempotent: array_append only if userId not already present.
      await _client.rpc(
        'mark_alert_viewed',
        params: {'p_alert_id': alertId, 'p_user_id': userId},
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'operational_alert');
    }
  }

  OperationalAlert _fromRow(Map<String, dynamic> row) {
    final viewedRaw = row['viewed_by_user_ids'];
    final viewedByUserIds = viewedRaw is List
        ? viewedRaw.cast<String>()
        : <String>[];

    return OperationalAlert(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      entityId: row['entity_id'] as String,
      contractId: row['contract_id'] as String,
      alertType: row['alert_type'] as String,
      severity: row['severity'] as String,
      triggeredAtUtc: DateTime.parse(row['triggered_at_utc'] as String),
      triggeringEventId: row['triggering_event_id'] as String?,
      traceId: row['trace_id'] as String?,
      context: Map<String, dynamic>.from(row['context'] as Map? ?? {}),
      status: row['status'] as String,
      acknowledgedAtUtc: row['acknowledged_at_utc'] != null
          ? DateTime.parse(row['acknowledged_at_utc'] as String)
          : null,
      acknowledgedByUserId: row['acknowledged_by_user_id'] as String?,
      resolvedAtUtc: row['resolved_at_utc'] != null
          ? DateTime.parse(row['resolved_at_utc'] as String)
          : null,
      viewedByUserIds: viewedByUserIds,
    );
  }
}
