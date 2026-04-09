/// Unit tests for [SupabaseAuthRepository].
// ignore_for_file: prefer_const_constructors
///
/// Verifies:
/// - AuthException → AuthFailureException mapping (no infra leaks — INV-18)
/// - getCurrentUser extracts tenantId exclusively from app_metadata (INV-1)
/// - Session lifecycle (signOut, refresh, authStatusStream)
/// - Offline connectivity handling (SocketException)
///
/// TDD: Written BEFORE implementation (Red phase).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:veraprob/domain/auth/auth_failure_exception.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/infrastructure/auth/supabase_auth_repository.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements supabase.SupabaseClient {}

class MockGoTrueClient extends Mock implements supabase.GoTrueClient {}

class MockSession extends Mock implements supabase.Session {}

class MockAuthStateChange extends Mock implements supabase.AuthState {}

// ── Helpers ──────────────────────────────────────────────────────────────────

supabase.User _createSecureUser() {
  return supabase.User(
    id: 'user-1',
    email: 'admin@veraprob.com',
    appMetadata: {'org_id': 'org-123', 'role': 'TENANT_ADMIN'},
    userMetadata: {'name': 'Admin'},
    aud: 'authenticated',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

supabase.User _createUserWithoutOrg() {
  return supabase.User(
    id: 'user-norg',
    email: 'norg@veraprob.com',
    appMetadata: {'role': 'OPERATOR'},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

supabase.Session _createSession(supabase.User user) {
  return supabase.Session(
    accessToken: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake.fake',
    tokenType: 'bearer',
    user: user,
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late SupabaseAuthRepository repo;

  final secureUser = _createSecureUser();
  final secureSession = _createSession(secureUser);

  setUpAll(() {
    registerFallbackValue(supabase.SignOutScope.global);
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    repo = SupabaseAuthRepository(mockClient);
  });

  group('SupabaseAuthRepository', () {
    // ── Constructor ───────────────────────────────────────────────────────

    test('constructor accepts a SupabaseClient', () {
      expect(repo, isNotNull);
    });

    // ── isAuthenticated ───────────────────────────────────────────────────

    group('isAuthenticated', () {
      test('returns true when session is active', () {
        when(() => mockAuth.currentSession).thenReturn(secureSession);
        expect(repo.isAuthenticated, isTrue);
      });

      test('returns false when session is null', () {
        when(() => mockAuth.currentSession).thenReturn(null);
        expect(repo.isAuthenticated, isFalse);
      });
    });

    // ── authStatusStream ──────────────────────────────────────────────────

    group('authStatusStream', () {
      test('emits true on sign-in event', () async {
        final controller = StreamController<supabase.AuthState>();
        when(
          () => mockAuth.onAuthStateChange,
        ).thenAnswer((_) => controller.stream);

        final future = repo.authStatusStream.first;
        controller.add(
          supabase.AuthState(supabase.AuthChangeEvent.signedIn, secureSession),
        );

        expect(await future, isTrue);
        await controller.close();
      });

      test('emits false on sign-out event', () async {
        final controller = StreamController<supabase.AuthState>();
        when(
          () => mockAuth.onAuthStateChange,
        ).thenAnswer((_) => controller.stream);

        final future = repo.authStatusStream.first;
        controller.add(
          supabase.AuthState(supabase.AuthChangeEvent.signedOut, null),
        );

        expect(await future, isFalse);
        await controller.close();
      });

      test('emits multiple status changes over time', () async {
        final controller = StreamController<supabase.AuthState>();
        when(
          () => mockAuth.onAuthStateChange,
        ).thenAnswer((_) => controller.stream);

        final emissions = <bool>[];
        final sub = repo.authStatusStream.listen(emissions.add);

        controller.add(
          supabase.AuthState(supabase.AuthChangeEvent.signedIn, secureSession),
        );
        controller.add(
          supabase.AuthState(supabase.AuthChangeEvent.signedOut, null),
        );
        controller.add(
          supabase.AuthState(supabase.AuthChangeEvent.signedIn, secureSession),
        );

        await Future.delayed(Duration.zero);
        expect(emissions, equals([true, false, true]));

        await sub.cancel();
        await controller.close();
      });
    });

    // ── signInWithPassword ────────────────────────────────────────────────

    group('signInWithPassword', () {
      test('returns userId on successful sign-in', () async {
        final response = supabase.AuthResponse(
          user: secureUser,
          session: secureSession,
        );
        when(
          () => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => response);

        final result = await repo.signInWithPassword(
          email: 'admin@veraprob.com',
          password: 'correct-horse-battery-staple',
        );

        expect(result, equals('user-1'));
      });

      test('throws AuthFailureException with generic message for '
          'invalid_credentials (anti-enumeration)', () async {
        when(
          () => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          const supabase.AuthException(
            'Invalid login credentials',
            code: 'invalid_credentials',
          ),
        );

        expect(
          () => repo.signInWithPassword(
            email: 'admin@veraprob.com',
            password: 'wrong',
          ),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              equals('Credenciais inválidas.'),
            ),
          ),
        );
      });

      test('throws AuthFailureException with generic message for '
          'user_not_found (anti-enumeration)', () async {
        when(
          () => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          const supabase.AuthException(
            'User not found',
            code: 'user_not_found',
          ),
        );

        expect(
          () => repo.signInWithPassword(
            email: 'nonexistent@veraprob.com',
            password: 'pass',
          ),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              equals('Credenciais inválidas.'),
            ),
          ),
        );
      });

      test('throws AuthFailureException for rate_limit_exceeded', () async {
        when(
          () => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          const supabase.AuthException(
            'Rate limit exceeded',
            code: 'rate_limit_exceeded',
          ),
        );

        expect(
          () => repo.signInWithPassword(
            email: 'admin@veraprob.com',
            password: 'pass',
          ),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              equals('Muitas tentativas. Tente novamente mais tarde.'),
            ),
          ),
        );
      });

      test('throws AuthFailureException for over_request_rate_limit', () async {
        when(
          () => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          const supabase.AuthException(
            'Over request rate limit',
            code: 'over_request_rate_limit',
          ),
        );

        expect(
          () => repo.signInWithPassword(
            email: 'admin@veraprob.com',
            password: 'pass',
          ),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              equals('Muitas tentativas. Tente novamente mais tarde.'),
            ),
          ),
        );
      });

      test(
        'throws AuthFailureException for unknown error codes (fallback)',
        () async {
          when(
            () => mockAuth.signInWithPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenThrow(
            const supabase.AuthException(
              'Some obscure error',
              code: 'obscure_error',
            ),
          );

          expect(
            () => repo.signInWithPassword(
              email: 'admin@veraprob.com',
              password: 'pass',
            ),
            throwsA(
              isA<AuthFailureException>().having(
                (e) => e.message,
                'message',
                equals('Erro de autenticação. Tente novamente.'),
              ),
            ),
          );
        },
      );

      test(
        'throws AuthFailureException for SocketException (offline)',
        () async {
          when(
            () => mockAuth.signInWithPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenThrow(const SocketException('No internet'));

          expect(
            () => repo.signInWithPassword(
              email: 'admin@veraprob.com',
              password: 'pass',
            ),
            throwsA(
              isA<AuthFailureException>().having(
                (e) => e.message,
                'message',
                equals('Erro de conexão com o servidor de autenticação.'),
              ),
            ),
          );
        },
      );
    });

    // ── signUpWithPassword ────────────────────────────────────────────────

    group('signUpWithPassword', () {
      test('returns userId on successful sign-up', () async {
        final response = supabase.AuthResponse(
          user: secureUser,
          session: null, // email confirmation pending
        );
        when(
          () => mockAuth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenAnswer((_) async => response);

        final result = await repo.signUpWithPassword(
          email: 'new@veraprob.com',
          password: 'secure-pass-123',
        );

        expect(result, equals('user-1'));
      });

      test('throws AuthFailureException for weak_password', () async {
        when(
          () => mockAuth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          const supabase.AuthException(
            'Password should be at least 6 characters',
            code: 'weak_password',
          ),
        );

        expect(
          () => repo.signUpWithPassword(
            email: 'new@veraprob.com',
            password: '123',
          ),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              equals('A senha não atende os requisitos de segurança.'),
            ),
          ),
        );
      });

      test('throws AuthFailureException for email_not_confirmed', () async {
        when(
          () => mockAuth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          const supabase.AuthException(
            'Email not confirmed',
            code: 'email_not_confirmed',
          ),
        );

        expect(
          () => repo.signUpWithPassword(
            email: 'unconfirmed@veraprob.com',
            password: 'secure-pass-123',
          ),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              equals('E-mail pendente de confirmação.'),
            ),
          ),
        );
      });

      test(
        'throws AuthFailureException for unknown sign-up errors (fallback)',
        () async {
          when(
            () => mockAuth.signUp(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenThrow(
            const supabase.AuthException(
              'Signup disabled',
              code: 'signup_disabled',
            ),
          );

          expect(
            () => repo.signUpWithPassword(
              email: 'new@veraprob.com',
              password: 'secure-pass-123',
            ),
            throwsA(
              isA<AuthFailureException>().having(
                (e) => e.message,
                'message',
                equals('Erro de autenticação. Tente novamente.'),
              ),
            ),
          );
        },
      );

      test(
        'throws AuthFailureException for SocketException (offline)',
        () async {
          when(
            () => mockAuth.signUp(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenThrow(const SocketException('No internet'));

          expect(
            () => repo.signUpWithPassword(
              email: 'new@veraprob.com',
              password: 'secure-pass-123',
            ),
            throwsA(
              isA<AuthFailureException>().having(
                (e) => e.message,
                'message',
                equals('Erro de conexão com o servidor de autenticação.'),
              ),
            ),
          );
        },
      );
    });

    // ── getCurrentUser ────────────────────────────────────────────────────

    group('getCurrentUser', () {
      test(
        'returns AuthUser with tenantId from app_metadata[org_id]',
        () async {
          when(() => mockAuth.currentUser).thenReturn(secureUser);

          final result = await repo.getCurrentUser();

          expect(result, isA<AuthUser>());
          expect(result!.id, equals('user-1'));
          expect(result.email, equals('admin@veraprob.com'));
          expect(result.tenantId, equals('org-123'));
        },
      );

      test(
        'throws AuthFailureException when app_metadata lacks org_id [INV-1]',
        () async {
          when(() => mockAuth.currentUser).thenReturn(_createUserWithoutOrg());

          expect(
            () => repo.getCurrentUser(),
            throwsA(
              isA<AuthFailureException>().having(
                (e) => e.message,
                'message',
                contains('organização'),
              ),
            ),
          );
        },
      );

      test('returns null when currentUser is null (no session)', () async {
        when(() => mockAuth.currentUser).thenReturn(null);

        final result = await repo.getCurrentUser();

        expect(result, isNull);
      });
    });

    // ── refreshSession ────────────────────────────────────────────────────

    group('refreshSession', () {
      test('completes successfully on valid refresh', () async {
        final emptyResponse = supabase.AuthResponse(
          user: _createSecureUser(),
          session: null,
        );
        when(
          () => mockAuth.refreshSession(),
        ).thenAnswer((_) async => emptyResponse);

        expect(repo.refreshSession(), completes);
      });

      test(
        'throws AuthFailureException when refresh fails with AuthException',
        () async {
          when(() => mockAuth.refreshSession()).thenThrow(
            const supabase.AuthException(
              'Session expired',
              code: 'session_expired',
            ),
          );

          expect(
            () => repo.refreshSession(),
            throwsA(isA<AuthFailureException>()),
          );
        },
      );

      test(
        'throws AuthFailureException for SocketException (offline)',
        () async {
          when(
            () => mockAuth.refreshSession(),
          ).thenThrow(const SocketException('No internet'));

          expect(
            () => repo.refreshSession(),
            throwsA(
              isA<AuthFailureException>().having(
                (e) => e.message,
                'message',
                equals('Erro de conexão com o servidor de autenticação.'),
              ),
            ),
          );
        },
      );
    });

    // ── signOut ───────────────────────────────────────────────────────────

    group('signOut', () {
      test('calls auth.signOut with GlobalSignOutScope', () async {
        when(
          () => mockAuth.signOut(scope: any(named: 'scope')),
        ).thenAnswer((_) async {});

        await repo.signOut();

        verify(
          () => mockAuth.signOut(scope: supabase.SignOutScope.global),
        ).called(1);
      });

      test('throws AuthFailureException when signOut fails', () async {
        when(() => mockAuth.signOut(scope: any(named: 'scope'))).thenThrow(
          const supabase.AuthException(
            'Sign out failed',
            code: 'sign_out_failed',
          ),
        );

        expect(() => repo.signOut(), throwsA(isA<AuthFailureException>()));
      });

      test(
        'throws AuthFailureException for SocketException (offline)',
        () async {
          when(
            () => mockAuth.signOut(scope: any(named: 'scope')),
          ).thenThrow(const SocketException('No internet'));

          expect(
            () => repo.signOut(),
            throwsA(
              isA<AuthFailureException>().having(
                (e) => e.message,
                'message',
                equals('Erro de conexão com o servidor de autenticação.'),
              ),
            ),
          );
        },
      );
    });

    // ── Audit Trail [INV-22] ─────────────────────────────────────────────

    group('Audit Trail [INV-22]', () {
      test(
        'failed login throws structured AuthFailureException for traceability',
        () async {
          when(
            () => mockAuth.signInWithPassword(
              email: any(named: 'email'),
              password: any(named: 'password'),
            ),
          ).thenThrow(
            const supabase.AuthException(
              'Invalid login credentials',
              code: 'invalid_credentials',
            ),
          );

          try {
            await repo.signInWithPassword(
              email: 'admin@veraprob.com',
              password: 'wrong',
            );
            fail('Expected AuthFailureException');
          } on AuthFailureException catch (e) {
            // Mensagem estruturada — rastreável no audit log
            expect(e.message, equals('Credenciais inválidas.'));
          }
        },
      );
    });
  });
}
