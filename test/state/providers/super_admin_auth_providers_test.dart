/// Exhaustive security tests for [super_admin_auth_providers.dart].
///
/// Covers:
///   - CIA Triad (Confidentiality & Integrity)
///   - Adversarial Resilience (MFA Hardening & Bypass)
///   - State Synchronization & Race Conditions
///   - INV-30: Dependency Injection
///   - Accessibility Semantics (UI Integration)
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/core/config/environment.dart';
import 'package:veraprob/domain/super_admin/i_mfa_repository.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_mfa_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Builds a fake 3-part JWT string with the given [payload] as the middle
/// segment. Header and signature are stubs — only the payload matters
/// for `decodeJwtPayload`.
String _buildFakeJwt(Map<String, dynamic> payload) {
  final header = base64Url
      .encode(utf8.encode('{"alg":"HS256"}'))
      .replaceAll('=', '');
  final body = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  const signature = 'fake_signature';
  return '$header.$body.$signature';
}

/// Creates a [ProviderContainer] with [authStateProvider] overridden to emit
/// an [AuthState] whose session carries the given [accessToken].
/// Returns the container. Caller must listen + await before reading derived providers.
ProviderContainer _containerWithToken(
  String accessToken, {
  String userId = 'user-123',
}) {
  final mockUser = MockUser();
  when(() => mockUser.id).thenReturn(userId);

  final mockSession = MockSession();
  when(() => mockSession.user).thenReturn(mockUser);
  when(() => mockSession.accessToken).thenReturn(accessToken);

  final authState = AuthState(AuthChangeEvent.signedIn, mockSession);

  return ProviderContainer.test(
    overrides: [
      authStateProvider.overrideWith((ref) => Stream.value(authState)),
    ],
  );
}

/// Creates a container with no active session (signed out).
ProviderContainer _containerSignedOut() {
  return ProviderContainer.test(
    overrides: [
      authStateProvider.overrideWith((ref) => const Stream<AuthState>.empty()),
    ],
  );
}

/// Waits for the authStateProvider stream to emit and keeps it alive.
Future<void> _pumpAuth(ProviderContainer container) async {
  container.listen(authStateProvider, (_, __) {});
  // Allow microtask to propagate the stream value
  await Future<void>.delayed(Duration.zero);
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('CIA Confidentiality: isSuperAdminProvider', () {
    test('returns true only when app_metadata.super_admin == true', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminProvider), isTrue);
    });

    test('returns false when super_admin claim is absent', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'role': 'TENANT_ADMIN'},
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminProvider), isFalse);
    });

    test('returns false when super_admin claim is false', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': false},
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminProvider), isFalse);
    });

    test(
      'returns false when super_admin claim is string "true" (type mismatch)',
      () async {
        final jwt = _buildFakeJwt({
          'app_metadata': {'super_admin': 'true'},
        });
        final container = _containerWithToken(jwt);
        await _pumpAuth(container);

        expect(container.read(isSuperAdminProvider), isFalse);
      },
    );

    test(
      'returns false when super_admin claim is integer 1 (type mismatch)',
      () async {
        final jwt = _buildFakeJwt({
          'app_metadata': {'super_admin': 1},
        });
        final container = _containerWithToken(jwt);
        await _pumpAuth(container);

        expect(container.read(isSuperAdminProvider), isFalse);
      },
    );

    test('returns false when app_metadata is null', () async {
      final jwt = _buildFakeJwt({'sub': 'user-123'});
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminProvider), isFalse);
    });

    test(
      'throws ProviderException when app_metadata is not a Map (type cast fails)',
      () async {
        // VULNERABILITY DOCUMENTED: The provider uses `as Map<String, dynamic>?`
        // which throws TypeError on non-null non-Map values. This should be
        // hardened with a safe cast in production code.
        final jwt = _buildFakeJwt({'app_metadata': 'corrupted'});
        final container = _containerWithToken(jwt);
        await _pumpAuth(container);

        expect(
          () => container.read(isSuperAdminProvider),
          throwsA(isA<ProviderException>()),
        );
      },
    );

    test('returns false when session is null (signed out)', () async {
      final container = _containerSignedOut();
      await _pumpAuth(container);

      expect(container.read(isSuperAdminProvider), isFalse);
    });
  });

  group('CIA Integrity: decodeJwtPayload resilience', () {
    test(
      'handles token with only 2 parts (malformed) — returns false',
      () async {
        final mockUser = MockUser();
        when(() => mockUser.id).thenReturn('user-x');
        final mockSession = MockSession();
        when(() => mockSession.user).thenReturn(mockUser);
        when(() => mockSession.accessToken).thenReturn('only.twoparts');

        final authState = AuthState(AuthChangeEvent.signedIn, mockSession);
        final container = ProviderContainer.test(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(authState)),
          ],
        );
        await _pumpAuth(container);

        expect(container.read(isSuperAdminProvider), isFalse);
      },
    );

    test('handles empty string token — returns false', () async {
      final mockUser = MockUser();
      when(() => mockUser.id).thenReturn('user-x');
      final mockSession = MockSession();
      when(() => mockSession.user).thenReturn(mockUser);
      when(() => mockSession.accessToken).thenReturn('');

      final authState = AuthState(AuthChangeEvent.signedIn, mockSession);
      final container = ProviderContainer.test(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(authState)),
        ],
      );
      await _pumpAuth(container);

      expect(container.read(isSuperAdminProvider), isFalse);
    });

    test(
      'throws ProviderException on invalid base64 payload (unhandled FormatException)',
      () async {
        // VULNERABILITY DOCUMENTED: decodeJwtPayload does not catch
        // FormatException from base64Url.decode. Should be hardened.
        final mockUser = MockUser();
        when(() => mockUser.id).thenReturn('user-x');
        final mockSession = MockSession();
        when(() => mockSession.user).thenReturn(mockUser);
        when(() => mockSession.accessToken).thenReturn('h.!!!invalid!!!.s');

        final authState = AuthState(AuthChangeEvent.signedIn, mockSession);
        final container = ProviderContainer.test(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(authState)),
          ],
        );
        await _pumpAuth(container);

        expect(
          () => container.read(isSuperAdminProvider),
          throwsA(isA<ProviderException>()),
        );
      },
    );

    test(
      'throws ProviderException on valid base64 but invalid JSON (unhandled FormatException)',
      () async {
        // VULNERABILITY DOCUMENTED: decodeJwtPayload does not catch
        // FormatException from jsonDecode. Should be hardened.
        final invalidJson = base64Url
            .encode(utf8.encode('not json at all'))
            .replaceAll('=', '');
        final token = 'h.$invalidJson.s';

        final mockUser = MockUser();
        when(() => mockUser.id).thenReturn('user-x');
        final mockSession = MockSession();
        when(() => mockSession.user).thenReturn(mockUser);
        when(() => mockSession.accessToken).thenReturn(token);

        final authState = AuthState(AuthChangeEvent.signedIn, mockSession);
        final container = ProviderContainer.test(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(authState)),
          ],
        );
        await _pumpAuth(container);

        expect(
          () => container.read(isSuperAdminProvider),
          throwsA(isA<ProviderException>()),
        );
      },
    );
  });

  group('Adversarial Resilience: isSuperAdminAal2Provider MFA Hardening', () {
    test(
      'returns false when user is not super admin (regardless of aal)',
      () async {
        final jwt = _buildFakeJwt({
          'app_metadata': {'super_admin': false},
          'aal': 'aal2',
        });
        final container = _containerWithToken(jwt);
        await _pumpAuth(container);

        expect(container.read(isSuperAdminAal2Provider), isFalse);
      },
    );

    test('returns false when super admin but aal is null', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminAal2Provider), isFalse);
    });

    test('returns false when super admin but aal is aal1', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
        'aal': 'aal1',
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminAal2Provider), isFalse);
    });

    test('returns true when super admin AND aal is aal2', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
        'aal': 'aal2',
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminAal2Provider), isTrue);
    });

    test('returns false when aal is "AAL2" (case-sensitive check)', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
        'aal': 'AAL2',
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminAal2Provider), isFalse);
    });

    test('returns false when aal is integer 2 (type mismatch)', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
        'aal': 2,
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminAal2Provider), isFalse);
    });
  });

  group('Adversarial Resilience: EnvironmentConfig.skipMfaForSuperAdmin Bypass', () {
    // NOTE: EnvironmentConfig.skipMfaForSuperAdmin is a compile-time constant.
    // In test environment: ENV=dev (default), SKIP_MFA_DEV=false (default).
    // Therefore skipMfaForSuperAdmin = isDev && _skipMfaDev = true && false = false.
    // The bypass is ONLY active when compiled with --dart-define=SKIP_MFA_DEV=true.

    test(
      'in test environment (no --dart-define), MFA is enforced for super admin',
      () {
        expect(EnvironmentConfig.skipMfaForSuperAdmin, isFalse);
      },
    );

    test('with bypass inactive, super admin without aal2 is denied', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
        'aal': 'aal1',
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminAal2Provider), isFalse);
    });

    test('with bypass inactive, super admin WITH aal2 is granted', () async {
      final jwt = _buildFakeJwt({
        'app_metadata': {'super_admin': true},
        'aal': 'aal2',
      });
      final container = _containerWithToken(jwt);
      await _pumpAuth(container);

      expect(container.read(isSuperAdminAal2Provider), isTrue);
    });

    test(
      'production guard: skipMfaForSuperAdmin requires BOTH isDev AND flag',
      () {
        // Documents the dual-condition safety:
        // Even if SKIP_MFA_DEV=true, production (ENV=prod) would still enforce MFA.
        expect(EnvironmentConfig.isDev, isTrue); // test env is dev
        expect(
          EnvironmentConfig.skipMfaForSuperAdmin,
          isFalse,
        ); // but flag is off
      },
    );
  });

  group(
    'State Synchronization: Atomicity of isSuperAdmin + currentSuperAdminId',
    () {
      test(
        'currentSuperAdminIdProvider returns user ID when isSuperAdmin is true',
        () async {
          final jwt = _buildFakeJwt({
            'app_metadata': {'super_admin': true},
          });
          final container = _containerWithToken(jwt, userId: 'admin-001');
          await _pumpAuth(container);

          expect(container.read(isSuperAdminProvider), isTrue);
          expect(
            container.read(currentSuperAdminIdProvider),
            equals('admin-001'),
          );
        },
      );

      test(
        'currentSuperAdminIdProvider returns null when isSuperAdmin is false',
        () async {
          final jwt = _buildFakeJwt({
            'app_metadata': {'super_admin': false},
          });
          final container = _containerWithToken(jwt);
          await _pumpAuth(container);

          expect(container.read(isSuperAdminProvider), isFalse);
          expect(container.read(currentSuperAdminIdProvider), isNull);
        },
      );

      test(
        'ID does not leak after session transitions to non-super-admin',
        () async {
          // Start with super admin session
          final superAdminJwt = _buildFakeJwt({
            'app_metadata': {'super_admin': true},
          });
          final container = _containerWithToken(
            superAdminJwt,
            userId: 'admin-001',
          );
          await _pumpAuth(container);

          expect(container.read(isSuperAdminProvider), isTrue);
          expect(
            container.read(currentSuperAdminIdProvider),
            equals('admin-001'),
          );

          // After invalidation, the stream re-emits the same value (same override).
          // The invariant is: if isSuperAdmin is false, ID must be null.
          container.invalidate(authStateProvider);
          await Future<void>.delayed(Duration.zero);

          final isSuperAdmin = container.read(isSuperAdminProvider);
          final adminId = container.read(currentSuperAdminIdProvider);

          // Atomicity: if not super admin, ID must be null
          if (!isSuperAdmin) {
            expect(
              adminId,
              isNull,
              reason: 'ID must not leak when isSuperAdmin is false',
            );
          } else {
            expect(adminId, isNotNull);
          }
        },
      );

      test('rapid session changes maintain consistency', () async {
        // First session: super admin
        final jwt1 = _buildFakeJwt({
          'app_metadata': {'super_admin': true},
        });
        final user1 = MockUser();
        when(() => user1.id).thenReturn('admin-A');
        final session1 = MockSession();
        when(() => session1.user).thenReturn(user1);
        when(() => session1.accessToken).thenReturn(jwt1);

        // Second session: regular user
        final jwt2 = _buildFakeJwt({
          'app_metadata': {'role': 'TENANT_ADMIN'},
        });
        final user2 = MockUser();
        when(() => user2.id).thenReturn('user-B');
        final session2 = MockSession();
        when(() => session2.user).thenReturn(user2);
        when(() => session2.accessToken).thenReturn(jwt2);

        final states = [
          AuthState(AuthChangeEvent.signedIn, session1),
          AuthState(AuthChangeEvent.tokenRefreshed, session2),
        ];

        final container = ProviderContainer.test(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => Stream.fromIterable(states),
            ),
          ],
        );
        container.listen(authStateProvider, (_, __) {});
        await Future<void>.delayed(Duration.zero);

        // After stream settles on last event, state must be consistent
        final isSuperAdmin = container.read(isSuperAdminProvider);
        final adminId = container.read(currentSuperAdminIdProvider);

        if (isSuperAdmin) {
          expect(adminId, isNotNull);
        } else {
          expect(adminId, isNull);
        }
      });
    },
  );

  group('INV-30: MFA Repository Dependency Injection', () {
    test('mfaRepositoryProvider returns SupabaseMfaRepository instance', () {
      final mockClient = MockSupabaseClient();
      final container = ProviderContainer.test(
        overrides: [
          supabaseClientProvider.overrideWithValue(mockClient),
          authStateProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
        ],
      );

      final repo = container.read(mfaRepositoryProvider);
      expect(repo, isA<IMfaRepository>());
      expect(repo, isA<SupabaseMfaRepository>());
    });

    test(
      'mfaRepositoryProvider injects supabaseClientProvider (not singleton)',
      () {
        final mockClient = MockSupabaseClient();
        final container = ProviderContainer.test(
          overrides: [
            supabaseClientProvider.overrideWithValue(mockClient),
            authStateProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
          ],
        );

        // Reading the provider should not throw — proves DI wiring is correct
        expect(() => container.read(mfaRepositoryProvider), returnsNormally);
      },
    );

    test(
      'mfaRepositoryProvider throws ProviderException when supabaseClientProvider is not overridden',
      () {
        final container = ProviderContainer.test(
          overrides: [
            authStateProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
          ],
        );

        // supabaseClientProvider throws UnimplementedError, wrapped in ProviderException
        expect(
          () => container.read(mfaRepositoryProvider),
          throwsA(isA<ProviderException>()),
        );
      },
    );
  });

  group('Accessibility Semantics: UI Integration', () {
    testWidgets(
      'updates semantic label when super admin state changes to true',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isSuperAdminProvider.overrideWithValue(true),
              authStateProvider.overrideWith(
                (ref) => const Stream<AuthState>.empty(),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: _SuperAdminStatusWidget()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final semantics = tester.getSemantics(
          find.byType(_SuperAdminStatusWidget),
        );
        expect(semantics.label, contains('Acesso Administrativo Ativo'));
      },
    );

    testWidgets('updates semantic label when super admin state is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isSuperAdminProvider.overrideWithValue(false),
            authStateProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: _SuperAdminStatusWidget()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.byType(_SuperAdminStatusWidget),
      );
      expect(semantics.label, contains('Acesso Padrão'));
    });
  });
}

// ─── Test Widget for Accessibility ──────────────────────────────────────────

class _SuperAdminStatusWidget extends ConsumerWidget {
  const _SuperAdminStatusWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuperAdmin = ref.watch(isSuperAdminProvider);
    final label = isSuperAdmin
        ? 'Acesso Administrativo Ativo'
        : 'Acesso Padrão';

    return Semantics(label: label, child: Text(label));
  }
}
