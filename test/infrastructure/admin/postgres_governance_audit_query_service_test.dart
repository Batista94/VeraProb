import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/admin/postgres_governance_audit_query_service.dart';

/// Pure row → DTO parsing for `get_tenant_governance_log`. The transport
/// (Supabase RPC call, org/permission/allowlist filtering) is enforced
/// server-side and exercised by pgTAP, not mocked here.
void main() {
  group('parseEntry', () {
    test('maps all explicit typed columns and coerces UTC', () {
      final entry = PostgresGovernanceAuditQueryService.parseEntry({
        'occurred_at': '2026-06-01T10:30:00+00:00',
        'event_type': 'MEMBER_DEACTIVATED',
        'actor_id': 'actor-1',
        'actor_email': 'admin@empresa.com',
        'target_user_id': 'target-1',
        'target_email': 'membro@empresa.com',
        'reason': 'Desligamento',
      });

      expect(entry.occurredAtUtc, DateTime.utc(2026, 6, 1, 10, 30));
      expect(entry.occurredAtUtc.isUtc, isTrue);
      expect(entry.eventType, 'MEMBER_DEACTIVATED');
      expect(entry.actorId, 'actor-1');
      expect(entry.actorEmail, 'admin@empresa.com');
      expect(entry.targetUserId, 'target-1');
      expect(entry.targetEmail, 'membro@empresa.com');
      expect(entry.reason, 'Desligamento');
    });

    test('nullable provenance columns default to null', () {
      final entry = PostgresGovernanceAuditQueryService.parseEntry({
        'occurred_at': '2026-06-01T10:30:00Z',
        'event_type': 'INVITATION_ACCEPTED',
        'actor_id': null,
        'actor_email': null,
        'target_user_id': null,
        'target_email': null,
        'reason': null,
      });

      expect(entry.actorId, isNull);
      expect(entry.actorEmail, isNull);
      expect(entry.targetUserId, isNull);
      expect(entry.targetEmail, isNull);
      expect(entry.reason, isNull);
    });
  });
}
