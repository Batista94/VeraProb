import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/reject_sanction_command.dart';
import 'package:veraprob/domain/enums/user_role.dart';

// Regras de Escrita:
// 1. Use DateTime.now().toUtc() em mocks (mesma linha).
// 2. Proibido importar lib/infrastructure em testes de application.

void main() {
  group('RejectSanctionCommand', () {
    test('carries the structured reasonCode (BUG-01 contract)', () {
      const command = RejectSanctionCommand(
        queueEntryId: 'entry-1',
        rejectedByUserId: 'auditor-1',
        actorEmail: 'auditor@veraprob.com',
        rejectionReason: 'GPS data was inconclusive for this route.',
        reasonCode: 'SENSOR_FAULT',
        callerRole: UserRole.auditor,
        organizationId: 'org-1',
        sessionId: 'session-1',
      );

      expect(command.reasonCode, 'SENSOR_FAULT');
      expect(command.rejectionReason, isNotEmpty);
    });
  });
}
