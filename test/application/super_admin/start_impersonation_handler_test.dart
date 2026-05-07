// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/features/super_admin/application/start_impersonation_handler.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

// ── Fake Clock ────────────────────────────────────────────────────────────────

class FakeDateTimeProvider implements IDateTimeProvider {
  DateTime _now;

  FakeDateTimeProvider(this._now);

  void advanceBy(Duration d) => _now = _now.add(d);

  @override
  DateTime nowUtc() => _now;

  @override
  DateTime nowBrazil() => _now;
}

// ── Test Fixtures ─────────────────────────────────────────────────────────────

const _kSessionId = 'session-uuid-test-01';
const _kTargetOrg = 'org-uuid-target-01';
const _kTicketId = 'TICKET-42';
const _kReason = 'Auditoria de segurança solicitada pelo cliente.';

// Server anchor — all time tests derive from this single reference point.
final _kServerNow = DateTime.utc(2026, 5, 5, 12, 0, 0);
final _kIssuedAt = _kServerNow;
final _kExpiresAt = _kServerNow.add(const Duration(hours: 1));

Map<String, dynamic> _validResponseBody() => {
  'session_id': 'imp-session-uuid-01',
  'target_org_id': _kTargetOrg,
  'target_org_name': 'Acme Logística Ltda',
  'impersonator_id': 'super-admin-uuid-01',
  'issued_at': _kIssuedAt.toIso8601String(),
  'expires_at': _kExpiresAt.toIso8601String(),
};

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late MockTenantValidationService mockTenantValidator;
  late FakeDateTimeProvider fakeClock;
  late StartImpersonationHandler handler;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    mockTenantValidator = MockTenantValidationService();
    fakeClock = FakeDateTimeProvider(_kServerNow);

    when(() => mockClient.functions).thenReturn(mockFunctions);

    // Default: INV-1 passes (superAdmin bypass scenario).
    when(
      () => mockTenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    handler = StartImpersonationHandler(
      mockClient,
      tenantValidator: mockTenantValidator,
      dateTimeProvider: fakeClock,
    );
  });

  Future<ImpersonationSessionInfo> call({
    UserRole role = UserRole.superAdmin,
    String ticketId = _kTicketId,
    String reason = _kReason,
    String targetOrgId = _kTargetOrg,
  }) => handler.handle(
    targetOrgId: targetOrgId,
    ticketId: ticketId,
    reason: reason,
    callerRole: role,
    sessionId: _kSessionId,
  );

  void stubFunctionResponse(int status, dynamic data) {
    when(
      () => mockFunctions.invoke(any(), body: any(named: 'body')),
    ).thenAnswer((_) async => FunctionResponse(status: status, data: data));
  }

  // ── Happy Path ──────────────────────────────────────────────────────────────

  group('happy path', () {
    setUp(() => stubFunctionResponse(200, _validResponseBody()));

    test(
      'superAdmin + valid inputs → returns ImpersonationSessionInfo',
      () async {
        final session = await call();

        expect(session.sessionId, equals('imp-session-uuid-01'));
        expect(session.targetOrgId, equals(_kTargetOrg));
        expect(session.targetOrgName, equals('Acme Logística Ltda'));
        expect(session.issuedAt, equals(_kIssuedAt));
        expect(session.expiresAt, equals(_kExpiresAt));
      },
    );

    test('session not expired when clock at issuance time', () async {
      final session = await call();
      expect(session.isExpired, isFalse);
      expect(session.remainingDuration, equals(const Duration(hours: 1)));
    });

    test('INV-1 assertTenantMatches called with correct args', () async {
      await call();

      verify(
        () => mockTenantValidator.assertTenantMatches(
          payloadOrgId: _kTargetOrg,
          sessionId: _kSessionId,
        ),
      ).called(1);
    });

    test('Edge Function invoked with correct payload', () async {
      await call();

      verify(
        () => mockFunctions.invoke(
          'issue-impersonation-jwt',
          body: {
            'target_org_id': _kTargetOrg,
            'ticket_id': _kTicketId,
            'reason': _kReason,
          },
        ),
      ).called(1);
    });

    test(
      'leading/trailing whitespace stripped from ticketId and reason',
      () async {
        await call(ticketId: '  $_kTicketId  ', reason: '  $_kReason  ');

        verify(
          () => mockFunctions.invoke(
            any(),
            body: {
              'target_org_id': _kTargetOrg,
              'ticket_id': _kTicketId,
              'reason': _kReason,
            },
          ),
        ).called(1);
      },
    );
  });

  // ── Scenario 1: Clock Drift (INV-6 / INV-15) ───────────────────────────────
  //
  // Device clock may be ahead of the server clock. Security must be
  // fail-closed: if nowUtc() >= expiresAt, the session is considered expired.

  group('Scenario 1 — Clock Drift: fail-closed on expired session (INV-6)', () {
    ImpersonationSessionInfo buildSession(IDateTimeProvider clock) =>
        ImpersonationSessionInfo(
          sessionId: 'imp-session-uuid-01',
          targetOrgId: _kTargetOrg,
          targetOrgName: 'Acme Logística',
          impersonatorId: 'super-admin-uuid-01',
          issuedAt: _kIssuedAt,
          expiresAt: _kExpiresAt,
          dateTimeProvider: clock,
        );

    test('clock 1h ahead of server (past expiresAt) → isExpired true', () {
      // _kExpiresAt = serverNow + 1h. Client clock = serverNow + 1h + 1s.
      final drifted = FakeDateTimeProvider(
        _kExpiresAt.add(const Duration(seconds: 1)),
      );

      final session = buildSession(drifted);

      expect(
        session.isExpired,
        isTrue,
        reason: 'Fail-closed: drifted clock past expiresAt must be expired',
      );
      expect(session.remainingDuration, equals(Duration.zero));
    });

    test('clock exactly at expiresAt → isExpired true (boundary, INV-6)', () {
      final exact = FakeDateTimeProvider(_kExpiresAt);
      final session = buildSession(exact);

      expect(
        session.isExpired,
        isTrue,
        reason: 'Boundary: nowUtc == expiresAt → Duration.zero → expired',
      );
    });

    test('1 second before expiry → session still valid', () {
      final almostExpired = FakeDateTimeProvider(
        _kExpiresAt.subtract(const Duration(seconds: 1)),
      );
      final session = buildSession(almostExpired);

      expect(session.isExpired, isFalse);
      expect(session.remainingDuration, equals(const Duration(seconds: 1)));
    });

    test('remainingDuration never goes negative — clamps to zero', () {
      final wayPast = FakeDateTimeProvider(
        _kExpiresAt.add(const Duration(hours: 24)),
      );
      final session = buildSession(wayPast);

      expect(session.remainingDuration, equals(Duration.zero));
    });
  });

  // ── Scenario 2: Contract Poisoning ─────────────────────────────────────────
  //
  // TDD: these tests FAIL on the current handler because DateTime.parse() and
  // `as String` casts throw TypeError/FormatException rather than DomainException.
  // Fix: wrap the ImpersonationSessionInfo construction in a try/catch that
  // converts those exceptions into DomainException.

  group('Scenario 2 — Contract Poisoning: malicious JSON from Edge Function', () {
    test('issued_at null → DomainException, not TypeError crash', () async {
      final poisoned = _validResponseBody()..['issued_at'] = null;
      stubFunctionResponse(200, poisoned);

      await expectLater(
        call(),
        throwsA(isA<DomainException>()),
        reason: 'Null field must be caught and wrapped, not crash the app',
      );
    });

    test('expires_at null → DomainException, not TypeError crash', () async {
      final poisoned = _validResponseBody()..['expires_at'] = null;
      stubFunctionResponse(200, poisoned);

      await expectLater(call(), throwsA(isA<DomainException>()));
    });

    test(
      'issued_at non-ISO string → DomainException, not FormatException',
      () async {
        final poisoned = _validResponseBody()..['issued_at'] = '31/12/2025';
        stubFunctionResponse(200, poisoned);

        await expectLater(
          call(),
          throwsA(isA<DomainException>()),
          reason:
              'Invalid date format must be caught and re-thrown as DomainException',
        );
      },
    );

    test(
      'expires_at non-ISO string → DomainException, not FormatException',
      () async {
        final poisoned = _validResponseBody()..['expires_at'] = 'amanhã';
        stubFunctionResponse(200, poisoned);

        await expectLater(call(), throwsA(isA<DomainException>()));
      },
    );

    test('session_id missing → DomainException, not TypeError crash', () async {
      final poisoned = Map<String, dynamic>.from(_validResponseBody())
        ..remove('session_id');
      stubFunctionResponse(200, poisoned);

      await expectLater(call(), throwsA(isA<DomainException>()));
    });

    test('response data is a List, not Map → DomainException', () async {
      stubFunctionResponse(200, ['unexpected', 'array']);

      await expectLater(call(), throwsA(isA<DomainException>()));
    });

    test('response data is a plain string → DomainException', () async {
      stubFunctionResponse(200, 'raw string payload');

      await expectLater(call(), throwsA(isA<DomainException>()));
    });
  });

  // ── Scenario 3: RBAC Attack ─────────────────────────────────────────────────

  group(
    'Scenario 3 — RBAC Attack: non-superAdmin roles blocked before Supabase',
    () {
      for (final role in [
        UserRole.admin,
        UserRole.operator,
        UserRole.auditor,
        UserRole.contractorViewer,
      ]) {
        test(
          '$role → DomainException(Unauthorized), Edge Fn never invoked',
          () async {
            await expectLater(
              call(role: role),
              throwsA(
                isA<DomainException>().having(
                  (e) => e.message,
                  'message',
                  contains('Unauthorized'),
                ),
              ),
            );

            verifyNever(
              () => mockFunctions.invoke(any(), body: any(named: 'body')),
            );
          },
        );
      }
    },
  );

  // ── Scenario 4: Idempotency Conflict (409) ──────────────────────────────────

  group('Scenario 4 — Idempotency Conflict: 409 active session', () {
    test('409 → DomainException with active-session message', () async {
      stubFunctionResponse(409, null);

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('sessão de impersonation ativa'),
              contains('Revogue'),
            ),
          ),
        ),
      );
    });

    test('409 → Edge Fn was invoked once (not short-circuited)', () async {
      stubFunctionResponse(409, null);

      await expectLater(call(), throwsA(isA<DomainException>()));

      verify(
        () => mockFunctions.invoke(any(), body: any(named: 'body')),
      ).called(1);
    });
  });

  // ── Scenario 5: INV-1 Short-Circuit ────────────────────────────────────────
  //
  // If TenantValidationService throws, the Edge Function must NEVER be called.
  // This is the primary invariant guard: no network I/O after a sovereignty
  // violation.

  group(
    'Scenario 5 — INV-1 Enforcement: tenant mismatch short-circuits Edge Fn',
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

      test('superAdmin role does NOT bypass INV-1 tenant check', () async {
        // superAdmin still subject to tenant assertion — the check runs before RBAC.
        await expectLater(
          call(role: UserRole.superAdmin),
          throwsA(isA<SovereigntyViolationException>()),
        );

        verifyNever(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        );
      });

      test(
        'INV-1 fires before input validation — ticketId guard never reached',
        () async {
          // Even an invalid ticketId never reaches validation because
          // the tenant check throws first.
          await expectLater(
            call(ticketId: ''),
            throwsA(isA<SovereigntyViolationException>()),
          );
        },
      );
    },
  );

  // ── Scenario 6: Network Chaos ───────────────────────────────────────────────

  group('Scenario 6 — Network Chaos: FunctionException fallback', () {
    test(
      'FunctionException with details → DomainException wraps details',
      () async {
        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenThrow(
          const FunctionException(
            status: 504,
            details: 'upstream timeout after 30s',
            reasonPhrase: 'Gateway Timeout',
          ),
        );

        await expectLater(
          call(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Falha ao iniciar impersonation'),
                contains('upstream timeout after 30s'),
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
      'FunctionException both null → DomainException still thrown (no rethrow)',
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

    test('FunctionException empty strings → DomainException thrown', () async {
      when(
        () => mockFunctions.invoke(any(), body: any(named: 'body')),
      ).thenThrow(
        const FunctionException(status: 500, details: '', reasonPhrase: ''),
      );

      await expectLater(call(), throwsA(isA<DomainException>()));
    });
  });

  // ── Input Validation Guards ─────────────────────────────────────────────────

  group('input validation — guards fire before Edge Fn', () {
    test(
      'empty ticketId → DomainException(ticket_id), Edge Fn never called',
      () async {
        await expectLater(
          call(ticketId: ''),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('ticket_id'),
            ),
          ),
        );
        verifyNever(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        );
      },
    );

    test(
      'whitespace-only ticketId → DomainException, Edge Fn never called',
      () async {
        await expectLater(
          call(ticketId: '   '),
          throwsA(isA<DomainException>()),
        );
        verifyNever(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        );
      },
    );

    test(
      'reason shorter than 10 chars → DomainException, Edge Fn never called',
      () async {
        await expectLater(
          call(reason: 'curta'),
          throwsA(isA<DomainException>()),
        );
        verifyNever(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        );
      },
    );

    test('reason exactly 10 chars → passes validation', () async {
      stubFunctionResponse(200, _validResponseBody());
      final session = await call(reason: '1234567890');
      expect(session.sessionId, isNotEmpty);
    });
  });

  // ── HTTP Status Guards (INV-26) ─────────────────────────────────────────────

  group('HTTP status guards — INV-26 Anti-Oracle', () {
    test('404 → DomainException(org não encontrada)', () async {
      stubFunctionResponse(404, null);

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('não encontrada'),
          ),
        ),
      );
    });

    test('500 + error field → DomainException echoes error field', () async {
      stubFunctionResponse(500, {'error': 'Internal server error'});

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Internal server error'),
          ),
        ),
      );
    });

    test('503 + null data → DomainException with fallback message', () async {
      stubFunctionResponse(503, null);

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Falha ao iniciar impersonation'),
          ),
        ),
      );
    });
  });
}
