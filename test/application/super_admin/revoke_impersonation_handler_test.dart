// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/features/super_admin/application/revoke_impersonation_handler.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kCallerSessionId = 'caller-session-uuid-01';
const _kImpersonationSessionId = 'imp-session-uuid-01';
const _kTargetOrg = 'org-uuid-target-01';
const _kReason = 'Auditoria encerrada pelo superadmin.';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late MockTenantValidationService mockTenantValidator;
  late RevokeImpersonationHandler handler;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    mockTenantValidator = MockTenantValidationService();

    when(() => mockClient.functions).thenReturn(mockFunctions);

    // Default: INV-1 passes (superAdmin bypass scenario).
    when(
      () => mockTenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    handler = RevokeImpersonationHandler(
      mockClient,
      tenantValidator: mockTenantValidator,
    );
  });

  Future<void> call({
    String impersonationSessionId = _kImpersonationSessionId,
    String targetOrgId = _kTargetOrg,
    String callerSessionId = _kCallerSessionId,
    String? reason,
  }) => handler.handle(
    impersonationSessionId: impersonationSessionId,
    targetOrgId: targetOrgId,
    callerSessionId: callerSessionId,
    reason: reason,
  );

  void stubFunctionResponse(int status, dynamic data) {
    when(
      () => mockFunctions.invoke(any(), body: any(named: 'body')),
    ).thenAnswer((_) async => FunctionResponse(status: status, data: data));
  }

  // ── Happy Path ──────────────────────────────────────────────────────────────

  group('happy path', () {
    setUp(() => stubFunctionResponse(200, null));

    test('200 → completes without exception', () async {
      await expectLater(call(), completes);
    });

    test('INV-1 assertTenantMatches called with correct args', () async {
      await call();

      verify(
        () => mockTenantValidator.assertTenantMatches(
          payloadOrgId: _kTargetOrg,
          sessionId: _kCallerSessionId,
        ),
      ).called(1);
    });

    test('Edge Function invoked with correct function name', () async {
      await call();

      verify(
        () => mockFunctions.invoke(
          'revoke-impersonation',
          body: any(named: 'body'),
        ),
      ).called(1);
    });
  });

  // ── Scenario 1: Double Revoke — Idempotency (409) ──────────────────────────
  //
  // A session already revoked must return a clean domain error, never
  // a raw HTTP status leak. The handler must not silently succeed on 409.

  group('Scenario 1 — Double Revoke: 409 idempotency guard', () {
    test('409 → DomainException("Sessão já foi revogada.")', () async {
      stubFunctionResponse(409, null);

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            equals('Sessão já foi revogada.'),
          ),
        ),
      );
    });

    test('409 → Edge Fn invoked once (not short-circuited by INV-1)', () async {
      stubFunctionResponse(409, null);

      await expectLater(call(), throwsA(isA<DomainException>()));

      verify(
        () => mockFunctions.invoke(any(), body: any(named: 'body')),
      ).called(1);
    });
  });

  // ── Scenario 2: Ghost Session Recovery (404) ────────────────────────────────
  //
  // Session deleted server-side before revoke call arrives (race condition
  // or already garbage-collected). Must surface a clear domain error.

  group('Scenario 2 — Ghost Session: 404 session not found', () {
    test('404 → DomainException("Sessão não encontrada.")', () async {
      stubFunctionResponse(404, null);

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            equals('Sessão não encontrada.'),
          ),
        ),
      );
    });
  });

  // ── Scenario 3: Payload Integrity ──────────────────────────────────────────
  //
  // The handler uses a conditional `if (reason != null)` to include the
  // 'reason' key. Both branches must be verified explicitly so a future
  // refactor that removes the conditional is caught immediately.

  group('Scenario 3 — Payload Integrity: reason field presence', () {
    test('with reason → body contains session_id AND reason', () async {
      stubFunctionResponse(200, null);

      await call(reason: _kReason);

      verify(
        () => mockFunctions.invoke(
          'revoke-impersonation',
          body: {'session_id': _kImpersonationSessionId, 'reason': _kReason},
        ),
      ).called(1);
    });

    test(
      'without reason (null) → body contains ONLY session_id, no reason key',
      () async {
        stubFunctionResponse(200, null);

        await call(reason: null);

        verify(
          () => mockFunctions.invoke(
            'revoke-impersonation',
            body: {'session_id': _kImpersonationSessionId},
          ),
        ).called(1);
      },
    );
  });

  // ── Scenario 4: Infrastructure Failure (500 / Network Error) ───────────────
  //
  // Raw HTTP error details and FunctionException internals must never reach
  // the caller. All paths must produce a DomainException (INV-10).

  group('Scenario 4 — Infrastructure Failure: no raw leaks (INV-10)', () {
    test(
      '500 + error field → DomainException echoes server error field',
      () async {
        stubFunctionResponse(500, {'error': 'Database unavailable'});

        await expectLater(
          call(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Database unavailable'),
            ),
          ),
        );
      },
    );

    test('500 + null data → DomainException with fallback message', () async {
      stubFunctionResponse(500, null);

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Falha ao revogar sessão'),
          ),
        ),
      );
    });

    test(
      'FunctionException with details → DomainException wraps details, no raw leak',
      () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenThrow(
          const FunctionException(
            status: 503,
            details: 'connection refused at edge worker',
            reasonPhrase: 'Service Unavailable',
          ),
        );

        await expectLater(
          call(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Falha ao revogar sessão'),
                contains('connection refused at edge worker'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'FunctionException null details → falls back to reasonPhrase',
      () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenThrow(
          const FunctionException(
            status: 503,
            details: null,
            reasonPhrase: 'Service Unavailable',
          ),
        );

        await expectLater(
          call(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Service Unavailable'),
            ),
          ),
        );
      },
    );

    test(
      'FunctionException both null → DomainException thrown, no raw rethrow',
      () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenThrow(
          const FunctionException(
            status: 500,
            details: null,
            reasonPhrase: null,
          ),
        );

        await expectLater(
          call(),
          throwsA(isA<DomainException>()),
          reason:
              'Must not leak raw FunctionException even when both fields null',
        );
      },
    );
  });

  // ── Scenario 5: INV-1 Validation ───────────────────────────────────────────
  //
  // callerSessionId is the token that proves the caller owns the org.
  // A stolen token must not allow revoking legitimate sessions.
  // The Edge Fn must NEVER be called after a sovereignty violation.

  group(
    'Scenario 5 — INV-1 Enforcement: stolen token cannot revoke sessions',
    () {
      setUp(() {
        when(
          () => mockTenantValidator.assertTenantMatches(
            payloadOrgId: any(named: 'payloadOrgId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenThrow(
          const SovereigntyViolationException(
            payloadOrgId: 'org-attacker',
            jwtOrgId: 'org-victim',
          ),
        );
      });

      test('SovereigntyViolationException propagates to caller', () async {
        await expectLater(
          call(),
          throwsA(isA<SovereigntyViolationException>()),
        );
      });

      test('Edge Function NEVER invoked after INV-1 violation', () async {
        await expectLater(call(), throwsA(anything));

        verifyNever(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        );
      });

      test(
        'stolen callerSessionId cannot revoke legitimate impersonation session',
        () async {
          await expectLater(
            call(callerSessionId: 'stolen-session-token'),
            throwsA(isA<SovereigntyViolationException>()),
          );

          verifyNever(
            () => mockFunctions.invoke(any(), body: any(named: 'body')),
          );
        },
      );

      test(
        'INV-1 fires before Edge Fn — no network I/O on sovereignty violation',
        () async {
          await expectLater(call(), throwsA(anything));

          verifyNever(
            () => mockFunctions.invoke(any(), body: any(named: 'body')),
          );
        },
      );
    },
  );
}
