import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/dispute_sanction_result.dart';

void main() {
  group('DisputeSanctionResult.fromJson', () {
    test('maps the RPC JSONB payload to the value object', () {
      final result = DisputeSanctionResult.fromJson(<String, dynamic>{
        'ledger_entry_id': 'ledger-1',
        'status': 'disputed',
        'resolution_due_at': '2026-08-20T12:00:00Z',
      });

      expect(result.ledgerEntryId, 'ledger-1');
      expect(result.finalQueueStatus, 'disputed');
      expect(result.resolutionDueAtUtc, DateTime.utc(2026, 8, 20, 12));
      expect(result.resolutionDueAtUtc.isUtc, isTrue);
    });
  });

  group('DisputeSanctionResult equality', () {
    final due = DateTime.utc(2026, 8, 20, 12);

    test('identical fields are equal', () {
      final a = DisputeSanctionResult(
        ledgerEntryId: 'ledger-1',
        finalQueueStatus: 'disputed',
        resolutionDueAtUtc: due,
      );
      final b = DisputeSanctionResult(
        ledgerEntryId: 'ledger-1',
        finalQueueStatus: 'disputed',
        resolutionDueAtUtc: due,
      );
      expect(a == b, isTrue);
    });

    test('a different ledger id breaks equality', () {
      final a = DisputeSanctionResult(
        ledgerEntryId: 'ledger-1',
        finalQueueStatus: 'disputed',
        resolutionDueAtUtc: due,
      );
      final b = DisputeSanctionResult(
        ledgerEntryId: 'ledger-2',
        finalQueueStatus: 'disputed',
        resolutionDueAtUtc: due,
      );
      expect(a == b, isFalse);
    });
  });
}
