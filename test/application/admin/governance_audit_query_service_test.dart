import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/governance_audit_query_service.dart';

// Regras de Escrita:
// 1. Use DateTime.now().toUtc() em mocks (mesma linha).
// 2. Proibido importar lib/infrastructure em testes de application.

void main() {
  group('GovernanceAuditEntry', () {
    test('carrega todos os campos opcionais como nulos por padrão', () {
      final now = DateTime.now().toUtc();
      final entry = GovernanceAuditEntry(
        occurredAtUtc: now,
        eventType: 'MEMBER_INVITED',
      );

      expect(entry.occurredAtUtc, now);
      expect(entry.eventType, 'MEMBER_INVITED');
      expect(entry.actorId, isNull);
      expect(entry.actorEmail, isNull);
      expect(entry.targetUserId, isNull);
      expect(entry.targetEmail, isNull);
      expect(entry.reason, isNull);
    });

    test('preserva todos os campos de proveniência quando fornecidos', () {
      final now = DateTime.now().toUtc();
      final entry = GovernanceAuditEntry(
        occurredAtUtc: now,
        eventType: 'MEMBER_REMOVED',
        actorId: 'actor-1',
        actorEmail: 'admin@empresa.com',
        targetUserId: 'target-1',
        targetEmail: 'membro@empresa.com',
        reason: 'Desligamento',
      );

      expect(entry.actorId, 'actor-1');
      expect(entry.actorEmail, 'admin@empresa.com');
      expect(entry.targetUserId, 'target-1');
      expect(entry.targetEmail, 'membro@empresa.com');
      expect(entry.reason, 'Desligamento');
    });
  });

  group('GovernanceEventCategory', () {
    test(
      'dbValue mapeia 1:1 com o allowlist da RPC get_tenant_governance_log',
      () {
        expect(GovernanceEventCategory.roles.dbValue, 'roles');
        expect(GovernanceEventCategory.members.dbValue, 'members');
        expect(GovernanceEventCategory.invites.dbValue, 'invites');
      },
    );
  });
}
