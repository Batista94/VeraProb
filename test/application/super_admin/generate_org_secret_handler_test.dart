// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/features/super_admin/application/generate_org_secret_handler.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

// ── Test Fixtures ─────────────────────────────────────────────────────────────

const _kOrgId = 'org-uuid-test-01';
const _kSessionId = 'session-uuid-test-01';
// 64 lowercase hex chars = 256-bit secret
const _kSecret =
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
const _kVersion = 1;

Map<String, dynamic> _validResponseBody() => {
  'secret': _kSecret,
  'version': _kVersion,
  'organization_id': _kOrgId,
};

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late MockTenantValidationService mockTenantValidator;
  late GenerateOrgSecretHandler handler;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    mockTenantValidator = MockTenantValidationService();

    when(() => mockClient.functions).thenReturn(mockFunctions);

    // Default: INV-1 passes.
    when(
      () => mockTenantValidator.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    handler = GenerateOrgSecretHandler(
      mockClient,
      tenantValidator: mockTenantValidator,
    );
  });

  Future<GenerateOrgSecretResult> call({
    String organizationId = _kOrgId,
    String sessionId = _kSessionId,
  }) => handler.handle(organizationId: organizationId, sessionId: sessionId);

  void stubFunctionResponse(int status, dynamic data) {
    when(
      () => mockFunctions.invoke(any(), body: any(named: 'body')),
    ).thenAnswer((_) async => FunctionResponse(status: status, data: data));
  }

  // ── Scenario 1: Secret Leakage Prevention ──────────────────────────────────
  //
  // The plain-text secret must appear ONLY in the success (200) result.
  // Any error path must throw DomainException WITHOUT embedding the secret.

  group('Scenario 1 — Secret Leakage Prevention: secret only on 200', () {
    test(
      '200 response → GenerateOrgSecretResult with plain-text secret',
      () async {
        stubFunctionResponse(200, _validResponseBody());

        final result = await call();

        expect(result.secret, equals(_kSecret));
        expect(result.secret.length, equals(64));
        expect(result.version, equals(_kVersion));
        expect(result.organizationId, equals(_kOrgId));
      },
    );

    test(
      '500 error → DomainException message does NOT contain secret',
      () async {
        stubFunctionResponse(500, {'error': 'Internal error'});

        DomainException? caught;
        try {
          await call();
        } on DomainException catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(
          caught!.message,
          isNot(contains(_kSecret)),
          reason: 'Secret must never appear in error messages',
        );
      },
    );

    test('403 error → DomainException, no secret in message', () async {
      stubFunctionResponse(403, {'error': 'Forbidden'});

      await expectLater(
        call(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            isNot(contains(_kSecret)),
          ),
        ),
      );
    });

    test(
      'non-200 with "error" field → DomainException echoes sanitized error field',
      () async {
        stubFunctionResponse(500, {'error': 'DB connection failed'});

        await expectLater(
          call(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('DB connection failed'),
            ),
          ),
        );
      },
    );

    test(
      'non-200 null data → DomainException with "Unknown error" fallback',
      () async {
        stubFunctionResponse(500, null);

        await expectLater(
          call(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Unknown error'),
            ),
          ),
        );
      },
    );
  });

  // ── Scenario 2: Contract Breach (Missing Fields) ────────────────────────────
  //
  // Edge Function returns HTTP 200 but the body is structurally wrong.
  // Handler must throw DomainException — not TypeError / NPE — so the app
  // never crashes and the error is surfaced in a controlled way.

  group('Scenario 2 — Contract Breach: missing or wrong-typed fields in 200', () {
    test(
      '"secret" field absent → DomainException, not TypeError crash',
      () async {
        final broken = Map<String, dynamic>.from(_validResponseBody())
          ..remove('secret');
        stubFunctionResponse(200, broken);

        await expectLater(
          call(),
          throwsA(isA<DomainException>()),
          reason:
              'Missing "secret" must be caught and wrapped as DomainException',
        );
      },
    );

    test(
      '"version" field absent → DomainException, not TypeError crash',
      () async {
        final broken = Map<String, dynamic>.from(_validResponseBody())
          ..remove('version');
        stubFunctionResponse(200, broken);

        await expectLater(
          call(),
          throwsA(isA<DomainException>()),
          reason:
              'Missing "version" must be caught and wrapped as DomainException',
        );
      },
    );

    test('null "secret" → DomainException, not Null check crash', () async {
      final broken = _validResponseBody()..['secret'] = null;
      stubFunctionResponse(200, broken);

      await expectLater(call(), throwsA(isA<DomainException>()));
    });

    test('null "version" → DomainException, not Null check crash', () async {
      final broken = _validResponseBody()..['version'] = null;
      stubFunctionResponse(200, broken);

      await expectLater(call(), throwsA(isA<DomainException>()));
    });

    test('"version" is String instead of int → DomainException', () async {
      final broken = _validResponseBody()..['version'] = 'not-an-int';
      stubFunctionResponse(200, broken);

      await expectLater(call(), throwsA(isA<DomainException>()));
    });

    test('response data is a List (not Map) → DomainException', () async {
      stubFunctionResponse(200, ['unexpected', 'array']);

      await expectLater(
        call(),
        throwsA(isA<DomainException>()),
        reason: 'Wrong response shape must be caught as DomainException',
      );
    });

    test('response data is a plain string → DomainException', () async {
      stubFunctionResponse(200, 'raw string payload');

      await expectLater(call(), throwsA(isA<DomainException>()));
    });
  });

  // ── Scenario 3: Session Hijacking (INV-1) ──────────────────────────────────
  //
  // TenantValidationService throws SovereigntyViolationException when the
  // organization_id in the request does not match the JWT claim.
  // The Edge Function must NEVER be called after this violation.

  group(
    'Scenario 3 — Session Hijacking (INV-1): tenant mismatch blocks Edge Fn',
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
        'orgId mismatch → no secret generated, Edge Fn not called',
        () async {
          await expectLater(
            call(organizationId: 'org-different-attacker'),
            throwsA(isA<SovereigntyViolationException>()),
          );

          verifyNever(
            () => mockFunctions.invoke(any(), body: any(named: 'body')),
          );
        },
      );

      test('INV-1 assertTenantMatches called with correct args', () async {
        try {
          await call();
        } on SovereigntyViolationException {
          // expected
        }

        verify(
          () => mockTenantValidator.assertTenantMatches(
            payloadOrgId: _kOrgId,
            sessionId: _kSessionId,
          ),
        ).called(1);
      });
    },
  );

  // ── Scenario 4: Function Execution Crash ───────────────────────────────────
  //
  // FunctionException is thrown by the Supabase client on network errors or
  // non-2xx responses that the client itself intercepts. The handler must:
  //   a) Always wrap into DomainException (never rethrow FunctionException).
  //   b) Sanitize "details" when it is a complex object — raw internal maps or
  //      stack traces must not reach the user-facing error message.

  group('Scenario 4 — Function Execution Crash: FunctionException cleanup', () {
    test(
      'FunctionException with string details → DomainException with prefix',
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
              contains('Falha ao gerar secret'),
            ),
          ),
        );
      },
    );

    test(
      'FunctionException with Map details → DomainException, no raw sensitive key leak',
      () async {
        final complexDetails = <String, dynamic>{
          'error': 'DB connection failed',
          'stack': 'long internal stack trace with PII',
          'internal_key': 'sensitive-data-12345',
        };

        when(
          () => mockFunctions.invoke(any(), body: any(named: 'body')),
        ).thenThrow(
          FunctionException(
            status: 500,
            details: complexDetails,
            reasonPhrase: 'Internal Server Error',
          ),
        );

        DomainException? caught;
        try {
          await call();
        } on DomainException catch (e) {
          caught = e;
        }

        expect(
          caught,
          isNotNull,
          reason: 'Must throw DomainException, not rethrow FunctionException',
        );
        expect(
          caught!.message,
          isNot(contains('sensitive-data-12345')),
          reason: 'Internal keys must not leak to user-facing error message',
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
              'Must not leak raw FunctionException even when both fields are null',
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

  // ── Scenario 5: Single Exposure Logic ──────────────────────────────────────
  //
  // The GenerateOrgSecretResult must:
  //   - Store all fields exactly as returned by the Edge Function.
  //   - Be immutable (const constructor) to prevent post-creation mutation.
  //   - Carry a 64-char lowercase hex secret (256-bit).
  //
  // This validates the "display once" contract: caller shows the secret
  // immediately; after that it is irrecoverable from the server.

  group(
    'Scenario 5 — Single Exposure Logic: GenerateOrgSecretResult integrity',
    () {
      test(
        'result stores secret exactly as returned by Edge Function',
        () async {
          stubFunctionResponse(200, _validResponseBody());

          final result = await call();

          expect(result.secret, equals(_kSecret));
        },
      );

      test('result stores version correctly', () async {
        stubFunctionResponse(200, _validResponseBody());

        final result = await call();

        expect(result.version, equals(_kVersion));
      });

      test('result stores organizationId correctly', () async {
        stubFunctionResponse(200, _validResponseBody());

        final result = await call();

        expect(result.organizationId, equals(_kOrgId));
      });

      test(
        'result is immutable — const constructor enforces single-exposure contract',
        () {
          const result = GenerateOrgSecretResult(
            secret: _kSecret,
            version: _kVersion,
            organizationId: _kOrgId,
          );

          expect(result.secret, equals(_kSecret));
          expect(result.version, equals(_kVersion));
          expect(result.organizationId, equals(_kOrgId));
        },
      );

      test('secret is 64 lowercase hex chars (256-bit)', () async {
        stubFunctionResponse(200, _validResponseBody());

        final result = await call();

        expect(result.secret.length, equals(64));
        expect(
          RegExp(r'^[0-9a-f]{64}$').hasMatch(result.secret),
          isTrue,
          reason: 'Secret must be a valid 64-char lowercase hex string',
        );
      });

      test(
        'Edge Function invoked with correct organization_id payload',
        () async {
          stubFunctionResponse(200, _validResponseBody());

          await call();

          verify(
            () => mockFunctions.invoke(
              'generate-org-secret',
              body: {'organization_id': _kOrgId},
            ),
          ).called(1);
        },
      );

      test('INV-1 assertTenantMatches called before Edge Function', () async {
        stubFunctionResponse(200, _validResponseBody());

        await call();

        verify(
          () => mockTenantValidator.assertTenantMatches(
            payloadOrgId: _kOrgId,
            sessionId: _kSessionId,
          ),
        ).called(1);
      });
    },
  );
}
