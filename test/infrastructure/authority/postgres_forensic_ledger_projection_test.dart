import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/projections/forensic_ledger_view.dart';
import 'package:veraprob/infrastructure/authority/postgres_forensic_ledger_projection.dart';

void main() {
  group('PostgresForensicLedgerProjection mapping (v2 smoke)', () {
    test('maps sla_audit_ledger_v2 row to ForensicLedgerEntry', () {
      final occurred = DateTime.utc(2026, 7, 13, 12, 0, 0);
      final entry = mapForensicLedgerRow({
        'id': '00000000-0000-0000-0000-00000000f001',
        'type': 'SYSTEM_AUTO_CLOSE',
        'operator_id': null,
        'payload': {'reason': 'zero_evidence', 'actor_type': 'system'},
        'occurred_at_utc': occurred.toIso8601String(),
      });

      expect(entry, isA<ForensicLedgerEntry>());
      expect(entry.decisionId, '00000000-0000-0000-0000-00000000f001');
      expect(entry.actionType, 'SYSTEM_AUTO_CLOSE');
      expect(entry.actorId, 'system');
      expect(entry.reason, 'zero_evidence');
      expect(entry.timestamp.toUtc(), occurred);
    });
  });
}
