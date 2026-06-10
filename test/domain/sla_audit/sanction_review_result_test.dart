import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_result.dart';

void main() {
  test('fromJson maps the RPC payload (status → finalQueueStatus)', () {
    final result = SanctionReviewResult.fromJson(const {
      'ledger_entry_id': 'ledger-1',
      'status': 'applied',
    });

    expect(result.ledgerEntryId, 'ledger-1');
    expect(result.finalQueueStatus, 'applied');
  });

  test('equality is value-based over ledgerEntryId + finalQueueStatus', () {
    const a = SanctionReviewResult(
      ledgerEntryId: 'ledger-1',
      finalQueueStatus: 'rejected',
    );
    const b = SanctionReviewResult(
      ledgerEntryId: 'ledger-1',
      finalQueueStatus: 'rejected',
    );
    const c = SanctionReviewResult(
      ledgerEntryId: 'ledger-2',
      finalQueueStatus: 'rejected',
    );

    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
