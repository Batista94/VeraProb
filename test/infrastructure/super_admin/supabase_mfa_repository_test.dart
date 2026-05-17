/// Unit tests for [SupabaseMfaRepository] — MFA operations (Phase 9.6.A.2).
///
/// Tests verify correct delegation to Supabase MFA API and circuit-breaker RPCs.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/super_admin/mfa_status.dart';
import 'package:veraprob/domain/super_admin/mfa_verification_result.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_mfa_repository.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockGoTrueMFAApi extends Mock implements GoTrueMFAApi {}

/// Fake that mimics [PostgrestFilterBuilder] when awaited.
///
/// Supabase's `rpc()` returns a [PostgrestFilterBuilder] which implements
/// [Future]. This fake resolves to the given [_result] when awaited.
class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  final dynamic _result;

  FakePostgrestFilterBuilder(this._result);

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    return Future<dynamic>.value(_result).then(onValue, onError: onError);
  }

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return Future<dynamic>.value(_result);
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) {
    return Future<dynamic>.value(_result).whenComplete(action);
  }

  @override
  Stream<dynamic> asStream() => Stream.value(_result);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    return Future<dynamic>.value(_result);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late MockGoTrueMFAApi mockMfa;
  late SupabaseMfaRepository repo;

  final fakeUser = User(
    id: 'user-1',
    appMetadata: const {'super_admin': true},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    mockMfa = MockGoTrueMFAApi();
    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.mfa).thenReturn(mockMfa);
    when(() => mockAuth.currentUser).thenReturn(fakeUser);
    repo = SupabaseMfaRepository(mockClient);
  });

  group('SupabaseMfaRepository', () {
    test('constructor accepts a single SupabaseClient', () {
      expect(repo, isNotNull);
    });

    // ── getMfaStatus ─────────────────────────────────────────────────────────

    group('getMfaStatus', () {
      test('returns needsEnrollment when no TOTP factors exist', () async {
        when(() => mockMfa.getAuthenticatorAssuranceLevel()).thenReturn(
          const AuthMFAGetAuthenticatorAssuranceLevelResponse(
            currentLevel: AuthenticatorAssuranceLevels.aal1,
            nextLevel: AuthenticatorAssuranceLevels.aal1,
            currentAuthenticationMethods: [],
          ),
        );
        when(() => mockMfa.listFactors()).thenAnswer(
          (_) async => AuthMFAListFactorsResponse(totp: [], phone: [], all: []),
        );
        when(
          () => mockClient.rpc<dynamic>(
            'check_mfa_lockout',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder({
            'failed_attempts': 0,
            'locked_until': null,
            'is_locked': false,
          }),
        );

        final status = await repo.getMfaStatus();

        expect(status.needsEnrollment, isTrue);
        expect(status.currentLevel, MfaAssuranceLevel.aal1);
        expect(status.hasEnrolledFactor, isFalse);
      });

      test('returns needsChallenge when TOTP enrolled but AAL1', () async {
        final factor = Factor(
          id: 'factor-123',
          friendlyName: 'VeraProb SuperAdmin TOTP',
          factorType: FactorType.totp,
          status: FactorStatus.verified,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        when(() => mockMfa.getAuthenticatorAssuranceLevel()).thenReturn(
          const AuthMFAGetAuthenticatorAssuranceLevelResponse(
            currentLevel: AuthenticatorAssuranceLevels.aal1,
            nextLevel: AuthenticatorAssuranceLevels.aal2,
            currentAuthenticationMethods: [],
          ),
        );
        when(() => mockMfa.listFactors()).thenAnswer(
          (_) async => AuthMFAListFactorsResponse(
            totp: [factor],
            phone: [],
            all: [factor],
          ),
        );
        when(
          () => mockClient.rpc<dynamic>(
            'check_mfa_lockout',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder({
            'failed_attempts': 0,
            'locked_until': null,
            'is_locked': false,
          }),
        );

        final status = await repo.getMfaStatus();

        expect(status.needsChallenge, isTrue);
        expect(status.hasEnrolledFactor, isTrue);
        expect(status.factorId, 'factor-123');
      });
    });

    // ── verifyChallenge ─────────────────────────────────────────────────────

    group('verifyChallenge', () {
      test('returns failure immediately when locked out', () async {
        when(
          () => mockClient.rpc<dynamic>(
            'check_mfa_lockout',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder({
            'failed_attempts': 5,
            'locked_until': DateTime.utc(2026, 3, 27, 13, 0).toIso8601String(),
            'is_locked': true,
          }),
        );

        final result = await repo.verifyChallenge(
          factorId: 'factor-123',
          challengeId: 'challenge-abc',
          code: '123456',
        );

        expect(result, isA<MfaVerificationFailure>());
        final failure = result as MfaVerificationFailure;
        expect(failure.isLockedOut, isTrue);
        verifyNever(
          () => mockMfa.verify(
            factorId: any(named: 'factorId'),
            challengeId: any(named: 'challengeId'),
            code: any(named: 'code'),
          ),
        );
      });

      test('returns success and resets lockout on valid code', () async {
        when(
          () => mockClient.rpc<dynamic>(
            'check_mfa_lockout',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder({
            'failed_attempts': 0,
            'locked_until': null,
            'is_locked': false,
          }),
        );
        when(
          () => mockMfa.verify(
            factorId: 'factor-123',
            challengeId: 'challenge-abc',
            code: '123456',
          ),
        ).thenAnswer(
          (_) async => AuthMFAVerifyResponse(
            accessToken: 'new-access-token',
            tokenType: 'bearer',
            expiresIn: const Duration(hours: 1),
            refreshToken: 'new-refresh-token',
            user: fakeUser,
          ),
        );
        when(
          () => mockClient.rpc<dynamic>(
            'reset_mfa_lockout',
            params: any(named: 'params'),
          ),
        ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

        final result = await repo.verifyChallenge(
          factorId: 'factor-123',
          challengeId: 'challenge-abc',
          code: '123456',
        );

        expect(result, isA<MfaVerificationSuccess>());
        verify(
          () => mockClient.rpc<dynamic>(
            'reset_mfa_lockout',
            params: any(named: 'params'),
          ),
        ).called(1);
      });

      test('records failure and returns failure on invalid code', () async {
        when(
          () => mockClient.rpc<dynamic>(
            'check_mfa_lockout',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder({
            'failed_attempts': 0,
            'locked_until': null,
            'is_locked': false,
          }),
        );
        when(
          () => mockMfa.verify(
            factorId: 'factor-123',
            challengeId: 'challenge-abc',
            code: '000000',
          ),
        ).thenThrow(const AuthException('Invalid TOTP code'));
        when(
          () => mockClient.rpc<dynamic>(
            'record_mfa_failure',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder({
            'failed_attempts': 1,
            'locked_until': null,
            'is_locked': false,
          }),
        );

        final result = await repo.verifyChallenge(
          factorId: 'factor-123',
          challengeId: 'challenge-abc',
          code: '000000',
        );

        expect(result, isA<MfaVerificationFailure>());
        final failure = result as MfaVerificationFailure;
        expect(failure.failedAttempts, 1);
        expect(failure.isLockedOut, isFalse);
        verify(
          () => mockClient.rpc<dynamic>(
            'record_mfa_failure',
            params: any(named: 'params'),
          ),
        ).called(1);
      });

      // ── INV-6 — circuit-breaker pre-check is a hard short-circuit ──────────
      test(
        'pre-check lockout short-circuits BOTH mfa.verify AND record_mfa_failure',
        () async {
          when(
            () => mockClient.rpc<dynamic>(
              'check_mfa_lockout',
              params: any(named: 'params'),
            ),
          ).thenAnswer(
            (_) => FakePostgrestFilterBuilder({
              'failed_attempts': 5,
              'locked_until': DateTime.utc(
                2026,
                3,
                27,
                13,
                0,
              ).toIso8601String(),
              'is_locked': true,
            }),
          );

          final result = await repo.verifyChallenge(
            factorId: 'factor-123',
            challengeId: 'challenge-abc',
            code: '999999',
          );

          expect(result, isA<MfaVerificationFailure>());
          final failure = result as MfaVerificationFailure;
          expect(failure.isLockedOut, isTrue);
          expect(failure.failedAttempts, 5);

          verifyNever(
            () => mockMfa.verify(
              factorId: any(named: 'factorId'),
              challengeId: any(named: 'challengeId'),
              code: any(named: 'code'),
            ),
          );
          verifyNever(
            () => mockClient.rpc<dynamic>(
              'record_mfa_failure',
              params: any(named: 'params'),
            ),
          );
        },
      );

      // ── INV-6 — reset is called EXACTLY ONCE on success (not zero, not twice) ──
      test(
        'successful verification calls reset_mfa_lockout exactly 1×',
        () async {
          when(
            () => mockClient.rpc<dynamic>(
              'check_mfa_lockout',
              params: any(named: 'params'),
            ),
          ).thenAnswer(
            (_) => FakePostgrestFilterBuilder({
              'failed_attempts': 0,
              'locked_until': null,
              'is_locked': false,
            }),
          );
          when(
            () => mockMfa.verify(
              factorId: 'factor-123',
              challengeId: 'challenge-abc',
              code: '111111',
            ),
          ).thenAnswer(
            (_) async => AuthMFAVerifyResponse(
              accessToken: 'tok',
              tokenType: 'bearer',
              expiresIn: const Duration(hours: 1),
              refreshToken: 'rfr',
              user: fakeUser,
            ),
          );
          when(
            () => mockClient.rpc<dynamic>(
              'reset_mfa_lockout',
              params: any(named: 'params'),
            ),
          ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

          await repo.verifyChallenge(
            factorId: 'factor-123',
            challengeId: 'challenge-abc',
            code: '111111',
          );

          verify(
            () => mockClient.rpc<dynamic>(
              'reset_mfa_lockout',
              params: any(named: 'params'),
            ),
          ).called(1);
          verifyNever(
            () => mockClient.rpc<dynamic>(
              'record_mfa_failure',
              params: any(named: 'params'),
            ),
          );
        },
      );
    });
  });
}
