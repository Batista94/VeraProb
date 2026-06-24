import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/dispute_resolution_result.dart';

void main() {
  group('DisputeResolutionResult.fromJson', () {
    test('maps the terminal RPC payload (accept arc, no snapshot)', () {
      final result = DisputeResolutionResult.fromJson(<String, dynamic>{
        'ledger_entry_id': 'ledger-1',
        'status': 'rejected',
        'snapshot': null,
      });

      expect(result.ledgerEntryId, 'ledger-1');
      expect(result.finalQueueStatus, 'rejected');
      expect(result.snapshot, isNull);
      expect(result.evidenceHashes, isNull);
    });

    test('maps the overturn snapshot when present', () {
      final result = DisputeResolutionResult.fromJson(<String, dynamic>{
        'ledger_entry_id': 'ledger-2',
        'status': 'applied',
        'snapshot': <String, dynamic>{'verdict_type': 'DISPUTE_OVERTURNED'},
      });

      expect(result.finalQueueStatus, 'applied');
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!['verdict_type'], 'DISPUTE_OVERTURNED');
    });

    test('parses embedded evidence hashes when surfaced', () {
      final result = DisputeResolutionResult.fromJson(<String, dynamic>{
        'ledger_entry_id': 'ledger-3',
        'status': 'rejected',
        'evidence_hashes': <dynamic>['a' * 64, 'b' * 64],
      });

      expect(result.evidenceHashes, <String>['a' * 64, 'b' * 64]);
    });

    test('evidence hashes default to null when the key is absent', () {
      final result = DisputeResolutionResult.fromJson(<String, dynamic>{
        'ledger_entry_id': 'ledger-4',
        'status': 'pending',
      });

      expect(result.evidenceHashes, isNull);
    });
  });

  group('DisputeResolutionResult equality', () {
    test('evidence hashes participate in equality', () {
      const a = DisputeResolutionResult(
        ledgerEntryId: 'ledger-1',
        finalQueueStatus: 'rejected',
        evidenceHashes: ['a'],
      );
      const b = DisputeResolutionResult(
        ledgerEntryId: 'ledger-1',
        finalQueueStatus: 'rejected',
        evidenceHashes: ['b'],
      );
      expect(a == b, isFalse);
    });

    test('identical fields are equal', () {
      const a = DisputeResolutionResult(
        ledgerEntryId: 'ledger-1',
        finalQueueStatus: 'rejected',
      );
      const b = DisputeResolutionResult(
        ledgerEntryId: 'ledger-1',
        finalQueueStatus: 'rejected',
      );
      expect(a == b, isTrue);
    });
  });
}
