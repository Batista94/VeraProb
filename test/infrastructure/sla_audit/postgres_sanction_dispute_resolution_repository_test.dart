import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_dispute_resolution_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// Unit coverage for the single most security-critical Dart path in the atomic
/// dispute-resolution flow: translating the `resolve_dispute` RPC's PostgREST
/// error codes into typed domain exceptions (F-1, lead-reviewer). No live DB —
/// the `client.rpc` call is stubbed to throw, exercising the catch branch only.
void main() {
  late _MockSupabaseClient client;
  late PostgresSanctionDisputeResolutionRepository repo;

  setUp(() {
    client = _MockSupabaseClient();
    repo = PostgresSanctionDisputeResolutionRepository(client);
  });

  Future<void> Function() callResolve() =>
      () => repo.resolveDispute(
        organizationId: 'org-1',
        queueEntryId: 'entry-1',
        resolution: 'DISPUTE_ACCEPTED',
        resolutionReason: 'Contractor proved force majeure.',
        resolvedByUserId: 'auditor-1',
        actorEmail: 'auditor@veraprob.com',
        occurredAtUtc: DateTime.utc(2026, 8, 9, 12),
        idempotencyKey: 'entry-1:DISPUTE_ACCEPTED:SNAPSHOT',
      );

  void stubRpcThrows(PostgrestException e) {
    when(
      () =>
          client.rpc<Map<String, dynamic>>(any(), params: any(named: 'params')),
    ).thenThrow(e);
  }

  test(
    'P0001 + DETAIL IdempotencyProcessingException → IdempotencyProcessingException',
    () async {
      stubRpcThrows(
        const PostgrestException(
          message: 'This dispute has already been resolved by another auditor.',
          code: 'P0001',
          details: 'IdempotencyProcessingException',
        ),
      );

      await expectLater(
        callResolve()(),
        throwsA(
          isA<IdempotencyProcessingException>().having(
            (e) => e.idempotencyKey,
            'idempotencyKey',
            'entry-1:DISPUTE_ACCEPTED:SNAPSHOT',
          ),
        ),
      );
    },
  );

  test(
    'P0001 without the idempotency DETAIL is NOT swallowed as a concurrency loss',
    () async {
      stubRpcThrows(
        const PostgrestException(
          message: 'some other business rule violation',
          code: 'P0001',
          details: 'SomethingElse',
        ),
      );

      await expectLater(
        callResolve()(),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e,
            'is not IdempotencyProcessingException',
            isNot(isA<IdempotencyProcessingException>()),
          ),
        ),
      );
    },
  );

  test(
    '42501 (NULL-JWT / cross-tenant / wrong-role) → opaque SovereigntyViolationException (INV-26)',
    () async {
      stubRpcThrows(
        const PostgrestException(
          message: 'Dispute resolution rejected.',
          code: '42501',
        ),
      );

      await expectLater(
        callResolve()(),
        throwsA(isA<SovereigntyViolationException>()),
      );
    },
  );
}
