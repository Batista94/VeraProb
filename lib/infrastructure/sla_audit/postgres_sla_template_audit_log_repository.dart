import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/i_sla_template_audit_log_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_template_audit_entry.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [ISlaTemplateAuditLogRepository].
///
/// Single-row insert only. The table REVOKEs UPDATE/DELETE and a trigger
/// raises `restrict_violation` on any mutation (INV-3), so no other ops exist.
class PostgresSlaTemplateAuditLogRepository extends BasePostgresRepository
    implements ISlaTemplateAuditLogRepository {
  PostgresSlaTemplateAuditLogRepository(super.client);

  @override
  Future<void> append(SlaTemplateAuditEntry entry) async {
    try {
      await client.from('sla_template_audit_log').insert({
        'id': entry.id,
        'organization_id': entry.organizationId,
        'template_id': entry.templateId,
        'actor_session_id': entry.actorSessionId,
        'action': entry.action,
        'template_snapshot': entry.templateSnapshot,
        'occurred_at_utc': entry.occurredAtUtc.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'sla_template_audit_log',
      );
    }
  }
}
