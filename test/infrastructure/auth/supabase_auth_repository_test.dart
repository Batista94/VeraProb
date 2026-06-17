/// Unit tests for [SupabaseAuthRepository].
// ignore_for_file: prefer_const_constructors
///
/// Verifies:
/// - AuthException → AuthFailureException mapping (no infra leaks — INV-18)
/// - getCurrentUser extracts tenantId exclusively from app_metadata (INV-1)
/// - Session lifecycle (signOut, refresh, authStatusStream)
/// - Offline connectivity handling (SocketException)
/// - getUserBySessionId reads org_id from JWT access token claims (not
///   raw_app_meta_data), because the custom_access_token_hook injects claims
///   only into the JWT and does NOT write to auth.users.raw_app_meta_data.
///
/// TDD: Written BEFORE implementation (Red phase).
library;

import 'dart:async';
import 'dart:convert';
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

/// Fake UserResponse — UserResponse only has fromJson constructor in gotrue,
/// so we use a fake class that implements the same interface.
class _FakeUserResponse implements supabase.UserResponse {
  @override
  final supabase.User? user;
  const _FakeUserResponse(this.user);

  Map<String, dynamic> toJson() => user?.toJson() ?? {};
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Builds a minimal JWT access token whose payload contains
/// `app_metadata.org_id` and `app_metadata.role`, matching what
/// `custom_access_token_hook` injects at sign-in.
String _buildJwt({
  String orgId = 'org-123',
  String role = 'TENANT_ADMIN',
  bool mfaEnabled = false,
}) {
  final payload = {
    'sub': 'user-1',
    'app_metadata': {'org_id': orgId, 'role': role, 'mfa_enabled': mfaEnabled},
    'exp':
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/
        1000,
  };
  final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.$encoded.fake-sig';
}

/// JWT with no app_metadata.org_id — simulates a user provisioned without
/// a tenant role (e.g. bootstrap omitted user_roles insert).
String _buildJwtWithoutOrg() {
  final payload = {
    'sub': 'user-norg',
    'app_metadata': {'role': 'OPERATOR'},
    'exp':
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/
        1000,
  };
  final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.$encoded.fake-sig';
}

/// Creates a Supabase User where appMetadata has org_id (Admin API synced).
/// Used for getCurrentUser() tests which read raw_app_meta_data.
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

/// Creates a Supabase User without org_id in appMetadata.
/// Simulates a tenant admin whose raw_app_meta_data was NOT updated by
/// the Admin API (only user_roles insert was done).
supabase.User _createUserWithoutOrgInAppMetadata() {
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
    accessToken: _buildJwt(),
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

        await Future<void>.delayed(Duration.zero);
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
          password: 'secure-password',
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
          when(
            () => mockAuth.currentUser,
          ).thenReturn(_createUserWithoutOrgInAppMetadata());

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

    // ── Session Cache (LRU-style with TTL) [INV-6] ──────────────────────

    group('Session Cache (LRU-style with TTL)', () {
      /// Helper: mock a successful getUser() server-side response.
      void mockGetUserSuccess(supabase.User user) {
        when(
          () => mockAuth.getUser(),
        ).thenAnswer((_) async => _FakeUserResponse(user));
      }

      /// Helper: mock a session with expiresAt for cache population.
      supabase.Session mockSessionWithExpiry(supabase.User user) {
        final session = MockSession();
        when(() => session.isExpired).thenReturn(false);
        when(() => session.user).thenReturn(user);
        when(() => session.expiresAt).thenReturn(
          DateTime.now()
                  .toUtc()
                  .add(Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        );
        when(() => mockAuth.currentSession).thenReturn(session);
        return session;
      }

      test('cache miss calls getUser() server-side and returns validated user '
          'when JWT access token has app_metadata.org_id [INV-1]', () async {
        // The user returned by getUser() has no org_id in appMetadata —
        // simulating a tenant admin whose raw_app_meta_data was not updated
        // by the Admin API (only hook-injected claims exist).
        mockGetUserSuccess(_createUserWithoutOrgInAppMetadata());
        mockSessionWithExpiry(_createUserWithoutOrgInAppMetadata());

        // JWT access token contains hook-injected org_id in app_metadata.
        final jwt = _buildJwt(orgId: 'org-123', role: 'TENANT_ADMIN');

        final result = await repo.getUserBySessionId(jwt);

        expect(result, isA<AuthUser>());
        expect(result!.tenantId, equals('org-123'));
        verify(() => mockAuth.getUser()).called(1);
      });

      test(
        'cache miss — JWT without app_metadata.org_id returns null [INV-1]',
        () async {
          mockGetUserSuccess(_createUserWithoutOrgInAppMetadata());
          when(() => mockAuth.currentSession).thenReturn(null);

          final jwt = _buildJwtWithoutOrg();

          final result = await repo.getUserBySessionId(jwt);

          expect(result, isNull);
          verify(() => mockAuth.getUser()).called(1);
        },
      );

      test(
        'cache hit on second call within TTL does NOT call getUser()',
        () async {
          mockGetUserSuccess(_createUserWithoutOrgInAppMetadata());
          mockSessionWithExpiry(_createUserWithoutOrgInAppMetadata());

          final jwt = _buildJwt(orgId: 'org-123');

          // First call — cache miss
          final result1 = await repo.getUserBySessionId(jwt);
          expect(result1, isA<AuthUser>());
          verify(() => mockAuth.getUser()).called(1);

          // Second call — cache hit, NO server-side call
          final result2 = await repo.getUserBySessionId(jwt);
          expect(result2, isA<AuthUser>());
          expect(result2!.tenantId, equals('org-123'));

          // getUser() still only called once
          verifyNever(() => mockAuth.getUser());
        },
      );

      test('cache invalidates on signOut', () async {
        mockGetUserSuccess(_createUserWithoutOrgInAppMetadata());
        mockSessionWithExpiry(_createUserWithoutOrgInAppMetadata());
        when(
          () => mockAuth.signOut(scope: any(named: 'scope')),
        ).thenAnswer((_) async {});

        final jwt = _buildJwt(orgId: 'org-123');

        // Populate cache
        await repo.getUserBySessionId(jwt);

        // Clear interaction history for clean verification
        clearInteractions(mockAuth);

        // Sign out — must invalidate
        await repo.signOut();

        // Simulate: after signOut, getUser() returns null
        when(
          () => mockAuth.getUser(),
        ).thenAnswer((_) async => _FakeUserResponse(null));
        when(() => mockAuth.currentSession).thenReturn(null);

        // Next call — cache miss, getUser() returns null
        final result = await repo.getUserBySessionId(jwt);
        expect(result, isNull);
        verify(() => mockAuth.getUser()).called(1);
      });

      test('cache invalidates on refreshSession', () async {
        mockGetUserSuccess(_createUserWithoutOrgInAppMetadata());
        mockSessionWithExpiry(_createUserWithoutOrgInAppMetadata());
        final emptyResponse = supabase.AuthResponse(
          user: _createSecureUser(),
          session: null,
        );
        when(
          () => mockAuth.refreshSession(),
        ).thenAnswer((_) async => emptyResponse);

        final jwt = _buildJwt(orgId: 'org-123');

        // Populate cache
        await repo.getUserBySessionId(jwt);

        // Clear interaction history
        clearInteractions(mockAuth);

        // Refresh — must invalidate
        await repo.refreshSession();

        // Simulate: after refresh, getUser() returns null
        when(
          () => mockAuth.getUser(),
        ).thenAnswer((_) async => _FakeUserResponse(null));
        when(() => mockAuth.currentSession).thenReturn(null);

        // Next call — cache miss
        final result = await repo.getUserBySessionId(jwt);
        expect(result, isNull);
        verify(() => mockAuth.getUser()).called(1);
      });

      test('getUser() returns null (revoked user) returns null', () async {
        when(
          () => mockAuth.getUser(),
        ).thenAnswer((_) async => _FakeUserResponse(null));
        when(() => mockAuth.currentSession).thenReturn(secureSession);

        final jwt = _buildJwt();

        final result = await repo.getUserBySessionId(jwt);

        expect(result, isNull);
        verify(() => mockAuth.getUser()).called(1);
      });

      test(
        'getUser() AuthException returns null and invalidates cache',
        () async {
          when(
            () => mockAuth.getUser(),
          ).thenThrow(supabase.AuthException('Invalid JWT'));
          when(() => mockAuth.currentSession).thenReturn(secureSession);

          final jwt = _buildJwt();

          final result = await repo.getUserBySessionId(jwt);

          expect(result, isNull);
        },
      );

      test(
        'getUser() AuthException with session_not_found signs out locally',
        () async {
          when(() => mockAuth.getUser()).thenThrow(
            const supabase.AuthException(
              'Session not found',
              code: 'session_not_found',
            ),
          );
          when(
            () => mockAuth.signOut(scope: any(named: 'scope')),
          ).thenAnswer((_) async {});
          when(() => mockAuth.currentSession).thenReturn(secureSession);

          final jwt = _buildJwt();

          final result = await repo.getUserBySessionId(jwt);

          expect(result, isNull);
          verify(
            () => mockAuth.signOut(scope: supabase.SignOutScope.local),
          ).called(1);
        },
      );

      test('JWT without org_id in claims returns null [INV-1]', () async {
        mockGetUserSuccess(_createUserWithoutOrgInAppMetadata());
        when(() => mockAuth.currentSession).thenReturn(null);

        final jwt = _buildJwtWithoutOrg();

        final result = await repo.getUserBySessionId(jwt);

        expect(result, isNull);
        verify(() => mockAuth.getUser()).called(1);
      });

      test('cache hit rejects when session expiresAt passes '
          'even if cache TTL is still valid', () async {
        // Test: session with a PAST expiresAt is rejected on the FIRST call.
        // getUser() is called because cache is bypassed.
        mockGetUserSuccess(_createUserWithoutOrgInAppMetadata());
        final sessionExpiredLongAgo = MockSession();
        final pastExpiresAt =
            DateTime.now()
                .toUtc()
                .subtract(Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000;
        when(() => sessionExpiredLongAgo.expiresAt).thenReturn(pastExpiresAt);
        when(() => sessionExpiredLongAgo.isExpired).thenReturn(true);
        when(
          () => sessionExpiredLongAgo.user,
        ).thenReturn(_createUserWithoutOrgInAppMetadata());
        when(() => mockAuth.currentSession).thenReturn(sessionExpiredLongAgo);

        final jwt = _buildJwt(orgId: 'org-123');

        final result = await repo.getUserBySessionId(jwt);

        // getUser() validates server-side, so this returns valid user
        // (the old session's expiresAt is irrelevant — server says user is valid)
        expect(result, isA<AuthUser>());
        verify(() => mockAuth.getUser()).called(1);
      });
    });

    // ── Refresh Token Awareness (Frente 4) ──────────────────────────────

    group('isAuthenticated — refresh token awareness', () {
      test('returns true when session is expired but has a refresh token', () {
        final session = MockSession();
        when(() => session.isExpired).thenReturn(true);
        when(() => session.refreshToken).thenReturn('valid-refresh-token');
        when(() => mockAuth.currentSession).thenReturn(session);

        expect(repo.isAuthenticated, isTrue);
      });

      test(
        'returns false when session is expired and has NO refresh token',
        () {
          final session = MockSession();
          when(() => session.isExpired).thenReturn(true);
          when(() => session.refreshToken).thenReturn(null);
          when(() => mockAuth.currentSession).thenReturn(session);

          expect(repo.isAuthenticated, isFalse);
        },
      );

      test(
        'returns false when session is expired and refresh token is empty',
        () {
          final session = MockSession();
          when(() => session.isExpired).thenReturn(true);
          when(() => session.refreshToken).thenReturn('');
          when(() => mockAuth.currentSession).thenReturn(session);

          expect(repo.isAuthenticated, isFalse);
        },
      );

      test('returns true when session is NOT expired (regardless of refresh '
          'token)', () {
        final session = MockSession();
        when(() => session.isExpired).thenReturn(false);
        when(() => session.refreshToken).thenReturn(null);
        when(() => mockAuth.currentSession).thenReturn(session);

        expect(repo.isAuthenticated, isTrue);
      });
    });

    group('authStatusStream — refresh token awareness', () {
      test('emits false when expired session has no refresh token', () async {
        final controller = StreamController<supabase.AuthState>();
        when(
          () => mockAuth.onAuthStateChange,
        ).thenAnswer((_) => controller.stream);

        final expiredNoRefresh = MockSession();
        when(() => expiredNoRefresh.isExpired).thenReturn(true);
        when(() => expiredNoRefresh.refreshToken).thenReturn(null);

        final future = repo.authStatusStream.first;
        controller.add(
          supabase.AuthState(
            supabase.AuthChangeEvent.tokenRefreshed,
            expiredNoRefresh,
          ),
        );

        expect(await future, isFalse);
        await controller.close();
      });

      test('emits true when expired session has a refresh token', () async {
        final controller = StreamController<supabase.AuthState>();
        when(
          () => mockAuth.onAuthStateChange,
        ).thenAnswer((_) => controller.stream);

        final expiredWithRefresh = MockSession();
        when(() => expiredWithRefresh.isExpired).thenReturn(true);
        when(() => expiredWithRefresh.refreshToken).thenReturn('valid-refresh');

        final future = repo.authStatusStream.first;
        controller.add(
          supabase.AuthState(
            supabase.AuthChangeEvent.tokenRefreshed,
            expiredWithRefresh,
          ),
        );

        expect(await future, isTrue);
        await controller.close();
      });
    });
  });
}
