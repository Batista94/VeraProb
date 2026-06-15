import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/sla_audit/dispute_resolution_result.dart';
import 'package:veraprob/domain/sla_audit/sanction_dispute_resolution_repository.dart';

/// Contract fake mirroring the RPC: the first resolve wins; a concurrent second
/// resolve of the same entry observes a non-disputed status and raises
/// [IdempotencyProcessingException] (no second ledger fact).
class _FakeResolver implements SanctionDisputeResolutionRepository {
  final Set<String> _resolved = {};

  @override
  Future<DisputeResolutionResult> resolveDispute({
    required String organizationId,
    required String queueEntryId,
    required String resolution,
    required String? resolutionReason,
    required String? reasonCode,
    required String resolvedByUserId,
    required String actorEmail,
    required DateTime occurredAtUtc,
    required String idempotencyKey,
  }) async {
    if (!_resolved.add(queueEntryId)) {
      throw IdempotencyProcessingException(
        idempotencyKey: idempotencyKey,
        commandPath: 'resolve_dispute',
      );
    }
    return DisputeResolutionResult(
      ledgerEntryId: 'ledger-1',
      finalQueueStatus: resolution == 'DISPUTE_ACCEPTED'
          ? 'rejected'
          : 'applied',
    );
  }
}

void main() {
  group('SanctionDisputeResolutionRepository (port contract)', () {
    test(
      'accepts a disputed sanction and returns the terminal status',
      () async {
        final repo = _FakeResolver();
        final r = await repo.resolveDispute(
          organizationId: 'org-1',
          queueEntryId: 'q-1',
          resolution: 'DISPUTE_ACCEPTED',
          resolutionReason: 'aceito',
          reasonCode: 'THIRD_PARTY_INCIDENT',
          resolvedByUserId: 'u-1',
          actorEmail: 'a@x.com',
          occurredAtUtc: DateTime.utc(2026, 6, 1),
          idempotencyKey: 'q-1:DISPUTE_ACCEPTED',
        );
        expect(r.finalQueueStatus, 'rejected');
        expect(r.ledgerEntryId, 'ledger-1');
      },
    );

    test(
      'concurrent double-resolution loser raises IdempotencyProcessingException',
      () async {
        final repo = _FakeResolver();
        Future<Object> attempt() => repo
            .resolveDispute(
              organizationId: 'org-1',
              queueEntryId: 'q-1',
              resolution: 'DISPUTE_ACCEPTED',
              resolutionReason: 'x',
              reasonCode: 'THIRD_PARTY_INCIDENT',
              resolvedByUserId: 'u-1',
              actorEmail: 'a@x.com',
              occurredAtUtc: DateTime.utc(2026, 6, 1),
              idempotencyKey: 'q-1:DISPUTE_ACCEPTED',
            )
            .then<Object>((r) => r)
            .catchError((Object e) => e);

        final outcomes = await Future.wait([attempt(), attempt()]);
        expect(outcomes.whereType<DisputeResolutionResult>(), hasLength(1));
        expect(
          outcomes.whereType<IdempotencyProcessingException>(),
          hasLength(1),
        );
      },
    );

    test(
      'DisputeResolutionResult.fromJson maps overturn snapshot + hashes',
      () {
        final r = DisputeResolutionResult.fromJson({
          'ledger_entry_id': 'l-1',
          'status': 'applied',
          'snapshot': {'k': 'v'},
          'evidence_hashes': ['a' * 64],
        });
        expect(r.snapshot, {'k': 'v'});
        expect(r.evidenceHashes, ['a' * 64]);
      },
    );
  });
}
