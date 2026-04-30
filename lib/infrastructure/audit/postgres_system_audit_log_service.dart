import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';

/// Postgres implementation of [SystemAuditLogService].
///
/// Writes governance events to `system_audit_log` with before/after snapshots,
/// reason, actor_type, and impersonator_id.
///
/// INV-3: Append-only — DB rules prevent UPDATE/DELETE.
/// INV-6: TIMESTAMPTZ via DB default NOW().
class PostgresSystemAuditLogService implements SystemAuditLogService {
  final SupabaseClient _client;

  PostgresSystemAuditLogService(this._client);

  @override
  Future<void> logGovernanceChange({
    required String eventType,
    required String reason,
    required ActorType actorType,
    String? impersonatorId,
    required String organizationId,
    String? organizationName,
    required Map<String, Object?> oldSnapshot,
    required Map<String, Object?> newSnapshot,
    Map<String, Object?>? context,
    String? source,
  }) async {
    await _client.from('system_audit_log').insert({
      'event_type': eventType,
      'severity': 'info',
      'payload': {
        'before': oldSnapshot,
        'after': newSnapshot,
        // ignore: use_null_aware_elements
        if (context != null) 'context': context,
      },
      'source': source ?? 'flutter_web',
      'organization_id': organizationId,
      'organization_name': organizationName,
      'reason': reason,
      'actor_type': actorType.dbValue,
      // ignore: use_null_aware_elements
      if (impersonatorId != null) 'impersonator_id': impersonatorId,
    });
  }
}
