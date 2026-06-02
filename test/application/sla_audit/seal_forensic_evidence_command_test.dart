import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/seal_forensic_evidence_command.dart';

void main() {
  final occurred = DateTime.utc(2026, 8, 1, 12);

  group('SealForensicEvidenceCommand', () {
    test('captures all required fields', () {
      final cmd = SealForensicEvidenceCommand(
        organizationId: 'org-1',
        sessionId: 'session-1',
        contractId: 'contract-1',
        setId: 'set-1',
        verdictType: 'NO_SHOW_PENALTY',
        planVersion: 2,
        occurredAtUtc: DateTime.utc(2026, 8, 1, 12),
        sealedBy: 'user-1',
        idempotencyKey: 'idem-abc',
      );

      expect(cmd.organizationId, 'org-1');
      expect(cmd.sessionId, 'session-1');
      expect(cmd.contractId, 'contract-1');
      expect(cmd.setId, 'set-1');
      expect(cmd.verdictType, 'NO_SHOW_PENALTY');
      expect(cmd.planVersion, 2);
      expect(cmd.occurredAtUtc, DateTime.utc(2026, 8, 1, 12));
      expect(cmd.sealedBy, 'user-1');
      expect(cmd.idempotencyKey, 'idem-abc');
    });

    test('different idempotency keys produce distinct commands', () {
      final a = SealForensicEvidenceCommand(
        organizationId: 'org-1',
        sessionId: 'session-1',
        contractId: 'contract-1',
        setId: 'set-1',
        verdictType: 'NO_SHOW_PENALTY',
        planVersion: 1,
        occurredAtUtc: occurred,
        sealedBy: 'user-1',
        idempotencyKey: 'idem-1',
      );
      final b = SealForensicEvidenceCommand(
        organizationId: 'org-1',
        sessionId: 'session-1',
        contractId: 'contract-1',
        setId: 'set-1',
        verdictType: 'NO_SHOW_PENALTY',
        planVersion: 1,
        occurredAtUtc: occurred,
        sealedBy: 'user-1',
        idempotencyKey: 'idem-2',
      );

      expect(a.idempotencyKey, isNot(b.idempotencyKey));
    });
  });
}
