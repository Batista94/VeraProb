/// Unit tests for [SupabaseUserMapper].
///
/// Verifies that Supabase User → Domain AuthUser mapping:
/// - Extracts tenantId EXCLUSIVELY from app_metadata['org_id'] (INV-1)
/// - Rejects user_metadata for tenant isolation (anti-tampering)
/// - Handles null email gracefully (phone/OAuth logins)
/// - Throws AuthFailureException when org_id is missing
///
/// TDD: Written BEFORE implementation (Red phase).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:veraprob/domain/auth/auth_failure_exception.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/infrastructure/auth/supabase_user_mapper.dart';

void main() {
  group('SupabaseUserMapper', () {
    // ── Fixtures ───────────────────────────────────────────────────────────

    /// Secure user — org_id SOMENTE em app_metadata (hook-injetado)
    supabase.User createSecureUser() {
      return supabase.User(
        id: 'user-secure-1',
        email: 'admin@veraprob.com',
        appMetadata: {'org_id': 'org-123', 'role': 'TENANT_ADMIN'},
        userMetadata: {'name': 'Admin User'},
        aud: 'authenticated',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    }

    /// Tampered user — org_id SOMENTE em user_metadata (client-side injection)
    supabase.User createTamperedUser() {
      return supabase.User(
        id: 'user-hacker-1',
        email: 'hacker@evil.com',
        appMetadata: {}, // SEM org_id — vazio
        userMetadata: {'organization_id': 'org-STOLEN'}, // INJEÇÃO
        aud: 'authenticated',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    }

    /// Phone-only user — no email
    supabase.User createPhoneOnlyUser() {
      return supabase.User(
        id: 'user-phone-1',
        phone: '+5511999999999',
        appMetadata: {'org_id': 'org-456', 'role': 'OPERATOR'},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    }

    /// User with no org_id in app_metadata (incomplete onboarding)
    supabase.User createUserWithoutOrg() {
      return supabase.User(
        id: 'user-norg-1',
        email: 'norg@veraprob.com',
        appMetadata: {'role': 'OPERATOR'}, // Sem org_id
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    }

    /// User with MFA claim in app_metadata
    supabase.User createMfaUser() {
      return supabase.User(
        id: 'user-mfa-1',
        email: 'mfa@veraprob.com',
        appMetadata: {
          'org_id': 'org-789',
          'role': 'AUDITOR',
          'mfa_enabled': true,
        },
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    }

    /// Minimal user — appMetadata has no org_id (simulates tenant admin
    /// provisioned only via user_roles insert, without Admin API app_metadata
    /// update). Used to test mapToAuthUserFromJwtClaims.
    supabase.User createUserWithoutOrgInAppMetadata() {
      return supabase.User(
        id: 'user-jwt-1',
        email: 'jwt-admin@veraprob.com',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    }

    // ── Testes ─────────────────────────────────────────────────────────────

    group('mapToAuthUser', () {
      test('returns AuthUser with tenantId from app_metadata[org_id]', () {
        final user = createSecureUser();
        final result = SupabaseUserMapper.mapToAuthUser(user);

        expect(result, isA<AuthUser>());
        expect(result.id, equals('user-secure-1'));
        expect(result.email, equals('admin@veraprob.com'));
        expect(result.tenantId, equals('org-123'));
        expect(result.role, equals(UserRole.admin));
      });

      test('throws AuthFailureException when app_metadata lacks org_id', () {
        final user = createUserWithoutOrg();

        expect(
          () => SupabaseUserMapper.mapToAuthUser(user),
          throwsA(
            isA<AuthFailureException>().having(
              (e) => e.message,
              'message',
              contains('organização'),
            ),
          ),
        );
      });

      test(
        'IGNORES user_metadata[organization_id] — anti-tampering [INV-1]',
        () {
          final user = createTamperedUser();

          // Deve rejeitar — user_metadata não é fonte confiável para tenantId
          expect(
            () => SupabaseUserMapper.mapToAuthUser(user),
            throwsA(isA<AuthFailureException>()),
          );
        },
      );

      test('handles null email gracefully (phone/OAuth login)', () {
        final user = createPhoneOnlyUser();
        final result = SupabaseUserMapper.mapToAuthUser(user);

        expect(result.email, isNull);
        expect(result.tenantId, equals('org-456'));
        expect(result.role, equals(UserRole.operator));
      });

      test('maps TENANT_ADMIN role string to UserRole.admin', () {
        final user = supabase.User(
          id: 'u1',
          email: 'a@b.com',
          appMetadata: {'org_id': 'o1', 'role': 'TENANT_ADMIN'},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        final result = SupabaseUserMapper.mapToAuthUser(user);
        expect(result.role, equals(UserRole.admin));
      });

      test('maps OPERATOR role string to UserRole.operator', () {
        final user = supabase.User(
          id: 'u1',
          email: 'a@b.com',
          appMetadata: {'org_id': 'o1', 'role': 'OPERATOR'},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        final result = SupabaseUserMapper.mapToAuthUser(user);
        expect(result.role, equals(UserRole.operator));
      });

      test('maps AUDITOR role string to UserRole.auditor', () {
        final user = supabase.User(
          id: 'u1',
          email: 'a@b.com',
          appMetadata: {'org_id': 'o1', 'role': 'AUDITOR'},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        final result = SupabaseUserMapper.mapToAuthUser(user);
        expect(result.role, equals(UserRole.auditor));
      });

      test('sets isMfaEnabled from app_metadata mfa_enabled claim', () {
        final user = createMfaUser();
        final result = SupabaseUserMapper.mapToAuthUser(user);

        expect(result.isMfaEnabled, isTrue);
      });

      test('defaults isMfaEnabled to false when claim is absent', () {
        final user = createSecureUser();
        final result = SupabaseUserMapper.mapToAuthUser(user);

        expect(result.isMfaEnabled, isFalse);
      });

      test('handles unknown role string gracefully (null role)', () {
        final user = supabase.User(
          id: 'u1',
          email: 'a@b.com',
          appMetadata: {'org_id': 'o1', 'role': 'UNKNOWN_ROLE'},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        final result = SupabaseUserMapper.mapToAuthUser(user);
        expect(result.role, isNull);
      });
    });

    // ── mapToAuthUserFromJwtClaims ─────────────────────────────────────────

    group('mapToAuthUserFromJwtClaims', () {
      test(
        'returns AuthUser with tenantId from JWT app_metadata.org_id [INV-1]',
        () {
          final user = createUserWithoutOrgInAppMetadata();
          final jwtClaims = <String, dynamic>{
            'sub': 'user-jwt-1',
            'app_metadata': {
              'org_id': 'org-hook-injected',
              'role': 'TENANT_ADMIN',
            },
          };

          final result = SupabaseUserMapper.mapToAuthUserFromJwtClaims(
            user,
            jwtClaims,
          );

          expect(result.id, equals('user-jwt-1'));
          expect(result.tenantId, equals('org-hook-injected'));
          expect(result.role, equals(UserRole.admin));
          expect(result.isMfaEnabled, isFalse);
        },
      );

      test(
        'throws AuthFailureException when JWT app_metadata lacks org_id [INV-1]',
        () {
          final user = createUserWithoutOrgInAppMetadata();
          final jwtClaims = <String, dynamic>{
            'sub': 'user-jwt-1',
            'app_metadata': {'role': 'OPERATOR'},
          };

          expect(
            () =>
                SupabaseUserMapper.mapToAuthUserFromJwtClaims(user, jwtClaims),
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

      test(
        'throws AuthFailureException when JWT has no app_metadata key [INV-1]',
        () {
          final user = createUserWithoutOrgInAppMetadata();
          final jwtClaims = <String, dynamic>{'sub': 'user-jwt-1'};

          expect(
            () =>
                SupabaseUserMapper.mapToAuthUserFromJwtClaims(user, jwtClaims),
            throwsA(isA<AuthFailureException>()),
          );
        },
      );

      test('reads mfa_enabled from JWT app_metadata', () {
        final user = createUserWithoutOrgInAppMetadata();
        final jwtClaims = <String, dynamic>{
          'app_metadata': {
            'org_id': 'org-mfa',
            'role': 'AUDITOR',
            'mfa_enabled': true,
          },
        };

        final result = SupabaseUserMapper.mapToAuthUserFromJwtClaims(
          user,
          jwtClaims,
        );

        expect(result.isMfaEnabled, isTrue);
        expect(result.role, equals(UserRole.auditor));
      });

      test('uses user.id and user.email from the Supabase User object', () {
        final user = createUserWithoutOrgInAppMetadata();
        final jwtClaims = <String, dynamic>{
          'app_metadata': {'org_id': 'org-x', 'role': 'OPERATOR'},
        };

        final result = SupabaseUserMapper.mapToAuthUserFromJwtClaims(
          user,
          jwtClaims,
        );

        expect(result.id, equals('user-jwt-1'));
        expect(result.email, equals('jwt-admin@veraprob.com'));
      });

      test('handles unknown role string gracefully (null role)', () {
        final user = createUserWithoutOrgInAppMetadata();
        final jwtClaims = <String, dynamic>{
          'app_metadata': {'org_id': 'org-x', 'role': 'LEGACY_ROLE'},
        };

        final result = SupabaseUserMapper.mapToAuthUserFromJwtClaims(
          user,
          jwtClaims,
        );

        expect(result.role, isNull);
      });
    });
  });
}
