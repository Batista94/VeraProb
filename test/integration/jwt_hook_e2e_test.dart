// JWT Hook E2E Integration Tests — Phase 9.4.3
//
// Validates that the `custom_access_token_hook` Postgres function correctly
// injects JWT claims for every user type recognized by the system.
//
// Prerequisites: `supabase start` running locally.
// Run: flutter test test/integration/jwt_hook_e2e_test.dart
//
// Invariants covered:
//   INV-6  — Multi-tenant RLS: super admin authenticated client sees no tenant data
//   INV-10 — RLS Tenant Claim: top-level organization_id injected by hook
//   INV-20 — Dual-Key Isolation: hook nullifies tenant claims for super admin
//
// Hook behaviour under test (from 20260410000001_fix_jwt_hook_toplevel_claims.sql):
//   Layer 1 (super_admin_users match) →
//     app_metadata.super_admin=true, org_id=null, role=null, RETURN early
//   Layer 2 (user_roles match) →
//     top-level organization_id injected (INV-10)
//     app_metadata.{org_id, role, contractor_id} set
//   Layer 3 (no match — pending invite) →
//     app_metadata.{super_admin=false, org_id=null, role=null, contractor_id=null}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _uuid = Uuid();

// Sentinel org ID for the tenant user in this suite.
const _hookTestOrgId = '00000000-9900-0000-0000-000000000001';
const _tenantUserEmail = 'jwt_hook_tenant@veraprob.test';
const _superAdminEmail = 'jwt_hook_super_admin@veraprob.test';
const _pendingInviteEmail = 'jwt_hook_pending_invite@veraprob.test';
const _testPassword = 'TestPassword123!';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Creates (or fetches) a test user via the Auth admin API.
Future<String> _ensureUser(
  String email,
  String password, {
  required String supabaseUrl,
  required String serviceRoleKey,
}) async {
  final response = await http.post(
    Uri.parse('$supabaseUrl/auth/v1/admin/users'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
    }),
  );

  if (response.statusCode == 200 || response.statusCode == 201) {
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  if (response.statusCode == 422) {
    final listRes = await http.get(
      Uri.parse('$supabaseUrl/auth/v1/admin/users?email=$email'),
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
    );
    final users =
        (jsonDecode(listRes.body) as Map<String, dynamic>)['users'] as List<dynamic>;
    return (users.first as Map<String, dynamic>)['id'] as String;
  }

  throw Exception('Failed to create user $email: ${response.body}');
}

/// Signs in and returns an authenticated [SupabaseClient].
Future<SupabaseClient> _signIn(
  String email,
  String password, {
  required String supabaseUrl,
  required String anonKey,
}) async {
  final client = SupabaseClient(supabaseUrl, anonKey);
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

/// Decodes the payload segment of a JWT without verifying the signature.
Map<String, dynamic> _decodeJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return {};
  final normalized = base64Url.normalize(parts[1]);
  return jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
}

// ── Main ─────────────────────────────────────────────────────────────────────

void main() {
  group('JWT Hook E2E — Phase 9.4.3', () {
    bool supabaseRunning = false;
    late SupabaseClient adminClient;

    setUpAll(() async {
      supabaseRunning = await PostgresTestConfig.isSupabaseRunning();
      if (!supabaseRunning) return;

      adminClient = SupabaseClient(
        PostgresTestConfig.supabaseUrl,
        PostgresTestConfig.serviceRoleKey,
      );

      // ── Seed sentinel org ────────────────────────────────────────────────
      await adminClient.from('organizations').upsert(
        {
          'id': _hookTestOrgId,
          'name': 'JWT Hook Test Org',
          'document_number': 'JWTTEST001',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'id',
      );

      // ── Seed tenant user + role ──────────────────────────────────────────
      final tenantUserId = await _ensureUser(
        _tenantUserEmail,
        _testPassword,
        supabaseUrl: PostgresTestConfig.supabaseUrl,
        serviceRoleKey: PostgresTestConfig.serviceRoleKey,
      );
      await adminClient.from('user_roles').upsert(
        {
          'user_id': tenantUserId,
          'organization_id': _hookTestOrgId,
          'role': 'TENANT_ADMIN',
        },
        onConflict: 'user_id',
      );

      // ── Seed super admin user ─────────────────────────────────────────────
      final superAdminId = await _ensureUser(
        _superAdminEmail,
        _testPassword,
        supabaseUrl: PostgresTestConfig.supabaseUrl,
        serviceRoleKey: PostgresTestConfig.serviceRoleKey,
      );
      await adminClient
          .from('super_admin_users')
          .upsert({'user_id': superAdminId}, onConflict: 'user_id');

      // ── Seed pending-invite user (NOT in user_roles, NOT in super_admin_users)
      await _ensureUser(
        _pendingInviteEmail,
        _testPassword,
        supabaseUrl: PostgresTestConfig.supabaseUrl,
        serviceRoleKey: PostgresTestConfig.serviceRoleKey,
      );
      // Deliberately NOT inserting into user_roles or super_admin_users.
    });

    // ── Scenario 1: Tenant user — top-level + app_metadata claims ────────
    test(
      'Scenario 1 — INV-10: tenant sign-in injects top-level organization_id and app_metadata.org_id',
      skip: supabaseRunning ? null : 'Supabase not running',
      () async {
        final client = await _signIn(
          _tenantUserEmail,
          _testPassword,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          anonKey: PostgresTestConfig.supabaseAnonKey,
        );

        try {
          final session = client.auth.currentSession;
          expect(session, isNotNull, reason: 'Tenant client must be signed in');

          final payload = _decodeJwt(session!.accessToken);

          // INV-10: top-level organization_id claim used by all RLS policies.
          expect(
            payload['organization_id'],
            _hookTestOrgId,
            reason:
                'Hook must inject organization_id as top-level JWT claim (INV-10)',
          );

          // Flutter auth_providers._jwtAppMeta reads app_metadata.org_id.
          final appMeta = payload['app_metadata'] as Map<String, dynamic>?;
          expect(appMeta, isNotNull, reason: 'app_metadata must be present');
          expect(
            appMeta!['org_id']?.toString(),
            _hookTestOrgId,
            reason: 'app_metadata.org_id must match the sentinel org (currentOrganizationIdProvider)',
          );
          expect(
            appMeta['role'],
            'TENANT_ADMIN',
            reason: 'app_metadata.role must reflect user_roles.role',
          );
          expect(
            appMeta['super_admin'],
            isNot(true),
            reason: 'Tenant user must not have super_admin=true',
          );
        } finally {
          await client.auth.signOut();
        }
      },
    );

    // ── Scenario 2: Super admin — super_admin=true, tenant claims nullified
    test(
      'Scenario 2 — INV-20: super admin sign-in sets super_admin=true and nullifies org_id',
      skip: supabaseRunning ? null : 'Supabase not running',
      () async {
        final client = await _signIn(
          _superAdminEmail,
          _testPassword,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          anonKey: PostgresTestConfig.supabaseAnonKey,
        );

        try {
          final session = client.auth.currentSession;
          expect(session, isNotNull, reason: 'Super admin client must be signed in');

          final payload = _decodeJwt(session!.accessToken);
          final appMeta = payload['app_metadata'] as Map<String, dynamic>?;
          expect(appMeta, isNotNull, reason: 'app_metadata must be present');

          // isSuperAdminProvider reads app_metadata.super_admin.
          expect(
            appMeta!['super_admin'],
            isTrue,
            reason: 'Hook must set app_metadata.super_admin=true for super admins',
          );

          // currentOrganizationIdProvider must return null for super admins —
          // they have no tenant context.
          final orgId = appMeta['org_id'];
          expect(
            orgId == null || orgId.toString().isEmpty,
            isTrue,
            reason: 'app_metadata.org_id must be null for super admin (no tenant context)',
          );

          // No top-level organization_id — super admin is not tenant-scoped.
          final topLevelOrgId = payload['organization_id'];
          expect(
            topLevelOrgId == null || topLevelOrgId.toString().isEmpty,
            isTrue,
            reason: 'top-level organization_id must not be set for super admin',
          );

          // app_metadata.role must be null — super admin has no tenant role.
          expect(
            appMeta['role'],
            isNull,
            reason: 'app_metadata.role must be null for super admin',
          );
        } finally {
          await client.auth.signOut();
        }
      },
    );

    // ── Scenario 3: Super admin client → RLS blocks tenant-scoped queries ──
    test(
      'Scenario 3 — INV-6: super admin authenticated client cannot SELECT tenant-scoped contracts',
      skip: supabaseRunning ? null : 'Supabase not running',
      () async {
        // Seed a contract visible only to the hook test org.
        final contractId = _uuid.v4();
        await adminClient.from('contracts').insert({
          'id': contractId,
          'organization_id': _hookTestOrgId,
          'name': 'JWT Hook Visibility Test Contract',
          'contractor_id': _uuid.v4(),
          'status': 'draft',
          'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
          'valid_until_utc':
              DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
          'created_by_user_id': _uuid.v4(),
        });

        // Sign in as super admin using the anon key (NOT service_role).
        // Service_role bypasses RLS — this test validates the authenticated path.
        final superAdminClient = await _signIn(
          _superAdminEmail,
          _testPassword,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          anonKey: PostgresTestConfig.supabaseAnonKey,
        );

        try {
          // Super admin JWT has no organization_id — RLS policy
          // `organization_id = (auth.jwt() ->> 'organization_id')::uuid`
          // will compare against null, which never matches. Result must be empty.
          final result = await superAdminClient
              .from('contracts')
              .select('id')
              .eq('id', contractId);

          expect(
            result,
            isEmpty,
            reason:
                'Super admin authenticated session must not bypass tenant RLS — '
                'no organization_id in JWT means no contract rows returned (INV-6)',
          );
        } finally {
          await superAdminClient.auth.signOut();
        }
      },
    );

    // ── Scenario 4: Pending invite user — no tenant context in JWT ─────────
    test(
      'Scenario 4: pending invite user JWT has no org_id, no role, super_admin=false',
      skip: supabaseRunning ? null : 'Supabase not running',
      () async {
        final client = await _signIn(
          _pendingInviteEmail,
          _testPassword,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          anonKey: PostgresTestConfig.supabaseAnonKey,
        );

        try {
          final session = client.auth.currentSession;
          expect(session, isNotNull, reason: 'Pending invite client must be signed in');

          final payload = _decodeJwt(session!.accessToken);
          final appMeta = payload['app_metadata'] as Map<String, dynamic>?;

          // Hook Layer 3: user found in neither user_roles nor super_admin_users.
          // Sets super_admin=false, org_id=null, role=null.
          // Flutter auth screen should route this session to a holding/pending screen.
          expect(
            appMeta?['super_admin'],
            isNot(true),
            reason: 'Pending invite user must not have super_admin=true',
          );

          final orgId = appMeta?['org_id'];
          expect(
            orgId == null || orgId.toString().isEmpty,
            isTrue,
            reason:
                'Pending invite user must have no org_id — '
                'app must route them to holding screen, not tenant shell',
          );

          final role = appMeta?['role'];
          expect(
            role == null || role.toString().isEmpty,
            isTrue,
            reason: 'Pending invite user must have no role claim',
          );

          // With no organization_id claim, any RLS-gated table query must return empty.
          final contracts = await client
              .from('contracts')
              .select('id')
              .limit(1);
          expect(
            contracts,
            isEmpty,
            reason:
                'Pending invite user must see no data — RLS organization_id is null (INV-10)',
          );
        } finally {
          await client.auth.signOut();
        }
      },
    );
  });
}
