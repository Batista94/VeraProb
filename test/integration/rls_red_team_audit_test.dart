@Tags(['integration', 'postgres'])
library;
// Expanded RLS Sovereignty Red Team Audit — INV-1 & INV-20
//
// Validates strict multi-tenant isolation, partitioned ledger sovereignty,
// and PII masking (LGPD) across all sensitive tables and views.
//
// PREREQUISITES: `supabase start` running locally.
// RUN: flutter test test/integration/rls_red_team_audit_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();

// Stabilized Sentinel IDs for the Red Team session
late String _orgAId;
late String _orgBId;
late String _userAEmail;
late String _userBEmail;
late String _operatorEmail;
const _testPassword = 'RedTeamPassword123!';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'RLS Sovereignty Audit (Red Team Expansion)',
    skip: !isRunning ? 'Supabase local instance not detected' : null,
    () {
      SupabaseClient? adminClient;
      SupabaseClient? tenantAClient;
      SupabaseClient? tenantBClient;
      SupabaseClient? operatorClient;

      // Tracks auth user IDs created during setUpAll for cleanup in tearDownAll
      final List<String> createdUserIds = [];

      setUpAll(() async {
        final timestamp = DateTime.now()
            .toUtc()
            .microsecondsSinceEpoch
            .toString();
        _orgAId = _uuid.v4();
        _orgBId = _uuid.v4();
        _userAEmail = 'admin_a_$timestamp@veraprob.test';
        _userBEmail = 'admin_b_$timestamp@veraprob.test';
        _operatorEmail = 'operator_a_$timestamp@veraprob.test';

        adminClient = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );

        // ── Step 1: Provision Multi-Tenant Infrastructure ───────────────────
        await _ensureOrg(
          adminClient!,
          id: _orgAId,
          name: 'RedTeam — Target Alpha',
        );
        await _ensureOrg(
          adminClient!,
          id: _orgBId,
          name: 'RedTeam — Target Beta',
        );

        final userAId = await _ensureUser(
          adminClient!,
          email: _userAEmail,
          password: _testPassword,
        );
        final userBId = await _ensureUser(
          adminClient!,
          email: _userBEmail,
          password: _testPassword,
        );
        final operatorId = await _ensureUser(
          adminClient!,
          email: _operatorEmail,
          password: _testPassword,
        );

        // Track for teardown
        createdUserIds.addAll([userAId, userBId, operatorId]);

        await _assignRole(
          adminClient!,
          userId: userAId,
          orgId: _orgAId,
          role: 'TENANT_ADMIN',
        );
        await _assignRole(
          adminClient!,
          userId: userBId,
          orgId: _orgBId,
          role: 'TENANT_ADMIN',
        );
        await _assignRole(
          adminClient!,
          userId: operatorId,
          orgId: _orgAId,
          role: 'OPERATOR',
        );

        // ── Step 2: Seed Sensitive Forensic Data (Target Beta) ──────────────
        // We seed data in Org B that Org A should NEVER be able to see.
        final contractBId = _uuid.v4();
        await adminClient!.from('contracts').upsert({
          'id': contractBId,
          'organization_id': _orgBId,
          'name': 'Sovereignty Breach Target',
          'contractor_name': 'Beta Contractor PII Target',
          'status': 'active',
          'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
          'valid_until_utc': DateTime.now()
              .toUtc()
              .add(const Duration(days: 365))
              .toIso8601String(),
        });

        // Ledger V2 (Partitioned)
        await adminClient!.from('sla_audit_ledger_v2').insert({
          'organization_id': _orgBId,
          'type': 'SENSITIVE_PAYMENT_CLOSE',
          'contract_id': contractBId,
          'plan_version': 1,
          'operator_id': userBId,
          'payload': {'secret_fines_cents': 999999},
          'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
        });

        // Evaluation Traces
        await adminClient!.from('contractual_evaluation_traces').insert({
          'organization_id': _orgBId,
          'entity_id': 'SET-SECRET-001',
          'triggering_event_id': _uuid.v4(),
          'evaluated_at_utc': DateTime.now().toUtc().toIso8601String(),
          'engine_version': 'veraprob-core_v4',
          'decisions_jsonb': [
            {
              'outcome': 'SANCTION_RECOMMENDED',
              'reason': 'Late Arrival Breach',
            },
          ],
        });

        // Operational Alerts
        await adminClient!.from('operational_alerts').insert({
          'organization_id': _orgBId,
          'entity_id': 'SET-SECRET-001',
          'contract_id': contractBId,
          'alert_type': 'PENALTY_APPLIED',
          'severity': 'CRITICAL',
          'triggered_at_utc': DateTime.now().toUtc().toIso8601String(),
          'context': {
            'message': 'Unauthorized bypass attempt detected (simulated)',
            'attacker_mock': 'RedTeam',
          },
        });

        // Seed a contractor for LGPD PII testing (Target Alpha)
        await adminClient!.from('contractors').upsert({
          'id': '00000000-1111-0000-0000-0000000000C1',
          'organization_id': _orgAId,
          'name': 'PII Test Contractor',
          'contact_name': 'Legit Owner',
          'tax_id': '11444777000161',
          'primary_email': 'legit_owner@business.com',
        });

        // ── Step 3: Login to Tenants ───────────────────────────────────────
        tenantAClient = await _signIn(_userAEmail, _testPassword);
        tenantBClient = await _signIn(_userBEmail, _testPassword);
        operatorClient = await _signIn(_operatorEmail, _testPassword);
      });

      tearDownAll(() async {
        // ── Cleanup: Delete auth users created during this test session ──────
        // This prevents `invalid_credentials` ghost users from accumulating
        // across runs (even though emails are timestamped, keeping the DB clean
        // is forensic hygiene).
        for (final uid in createdUserIds) {
          await _deleteUser(uid, adminClient);
        }
        createdUserIds.clear();

        // Dispose tenant clients
        await tenantAClient?.auth.signOut();
        await tenantBClient?.auth.signOut();
        await operatorClient?.auth.signOut();
      });

      // ── Sanity Check ────────────────────────────────────────────────────────
      test(
        'SANITY — Availability: Tenant B can see their own ledger',
        () async {
          final res = await tenantBClient!
              .from('sla_audit_ledger_v2')
              .select('id');
          expect(
            res,
            isNotEmpty,
            reason:
                'Availability Failure: Tenant B blocked from their own data',
          );
        },
      );

      test('DEBUG — JWT Claims: Inspect claims for Tenant A', () async {
        final session = tenantAClient!.auth.currentSession;
        final jwt = session!.accessToken;
        final parts = jwt.split('.');
        String base64Str = parts[1];
        while (base64Str.length % 4 != 0) {
          base64Str += '=';
        }
        final payload =
            jsonDecode(
                  utf8.decode(
                    base64Decode(
                      base64Str.replaceAll('-', '+').replaceAll('_', '/'),
                    ),
                  ),
                )
                as Map<String, dynamic>;

        expect(payload['organization_id'], equals(_orgAId));
        expect(payload['app_metadata']['role'], equals('TENANT_ADMIN'));
      });

      // ═════════════════════════════════════════════════════════════════════════
      // AUDIT 1: Ledger Forensic Isolation (INV-1, INV-6)
      // ═════════════════════════════════════════════════════════════════════════
      test(
        'AUDIT 1 — Partitioned Ledger Sovereignty: Org A cannot read Org B ledger_v2',
        () async {
          final res = await tenantAClient!
              .from('sla_audit_ledger_v2')
              .select()
              .eq('organization_id', _orgBId);

          expect(
            res,
            isEmpty,
            reason:
                'RLS breach: Tenant Alpha accessed Tenant Beta ledger entries',
          );
        },
      );

      // ═════════════════════════════════════════════════════════════════════════
      // AUDIT 2: Explainability Isolation (INV-7)
      // ═════════════════════════════════════════════════════════════════════════
      test(
        'AUDIT 2 — Trace Explainability Isolation: Org A cannot read Org B evaluation traces',
        () async {
          final res = await tenantAClient!
              .from('contractual_evaluation_traces')
              .select()
              .eq('organization_id', _orgBId);

          expect(
            res,
            isEmpty,
            reason:
                'RLS breach: Tenant Alpha accessed Tenant Beta evaluation traces',
          );
        },
      );

      test(
        'AUDIT 3 — Alert Sovereignty: Org A cannot read Org B operational alerts',
        () async {
          final res = await tenantAClient!
              .from('operational_alerts')
              .select()
              .eq('organization_id', _orgBId);

          expect(
            res,
            isEmpty,
            reason:
                'RLS breach: Tenant Alpha accessed Tenant Beta operational alerts',
          );
        },
      );

      // ═════════════════════════════════════════════════════════════════════════
      // AUDIT 4: LGPD PII Masking (LGPD Compliance)
      // ═════════════════════════════════════════════════════════════════════════
      test(
        'AUDIT 4 — LGPD PII Masking: OPERATOR role sees masked CNPJ and Email',
        () async {
          const contractorId = '00000000-1111-0000-0000-0000000000C1';
          final res = await operatorClient!
              .from('contractors_view')
              .select('tax_id, primary_email')
              .eq('id', contractorId)
              .single();

          expect(
            res['tax_id'],
            equals('XX.XXX.XXX/XXXX-XX'),
            reason: 'LGPD Breach: OPERATOR saw raw CNPJ',
          );
          expect(
            res['primary_email'],
            contains('****@business.com'),
            reason: 'LGPD Breach: OPERATOR saw raw Email localpart',
          );
        },
      );

      test(
        'AUDIT 5 — LGPD PII Access: TENANT_ADMIN sees full PII details',
        () async {
          final res = await tenantAClient!
              .from('contractors_view')
              .select('tax_id, primary_email')
              .limit(1)
              .single();

          expect(
            res['tax_id'],
            isNot(equals('XX.XXX.XXX/XXXX-XX')),
            reason: 'UX Degradation: ADMIN saw masked CNPJ',
          );
          expect(
            res['primary_email'],
            isNot(contains('****')),
            reason: 'UX Degradation: ADMIN saw masked Email',
          );
        },
      );

      // ═════════════════════════════════════════════════════════════════════════
      // AUDIT 5: Sovereignty Penetration (Injection/Mismatches)
      // ═════════════════════════════════════════════════════════════════════════
      test(
        'AUDIT 6 — Sovereignty Injection: Rejected when Org A attempts to insert Ledger for Org B',
        () async {
          // Payload attempts to bypass RLS by specifying Org B ID while holding Org A JWT
          await expectLater(
            () async => tenantAClient!.from('sla_audit_ledger_v2').insert({
              'organization_id': _orgBId,
              'type': 'MALICIOUS_INJECTION',
              'contract_id': _uuid.v4(),
              'plan_version': 1,
              'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
            }),
            throwsA(isA<PostgrestException>()),
            reason:
                'Security breach: RLS WITH CHECK failed to reject mismatched organization_id',
          );
        },
      );

      // ═════════════════════════════════════════════════════════════════════════
      // AUDIT 6: Forensic Immutability (INV-1, INV-7)
      // ═════════════════════════════════════════════════════════════════════════
      test(
        'AUDIT 7 — Forensic Immutability: Even service_role cannot DELETE from Ledger V2',
        () async {
          // Trigger-based immutability check
          final ledgerId = _uuid.v4();
          await adminClient!.from('sla_audit_ledger_v2').insert({
            'id': ledgerId,
            'organization_id': _orgAId,
            'type': 'IMMUTABILITY_PROBE',
            'contract_id': _uuid.v4(),
            'plan_version': 1,
            'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
          });

          await expectLater(
            () async => adminClient!
                .from('sla_audit_ledger_v2')
                .delete()
                .eq('id', ledgerId),
            throwsA(isA<PostgrestException>()),
            reason:
                'Forensic Breach: Immutability trigger failed to block DELETE for ledger_v2',
          );
        },
      );
    },
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Creates a user via the Supabase Auth Admin REST API.
/// Uses the [serviceRoleKey] (not the anon key) — required for admin endpoints.
/// Returns the new user's UUID.
Future<String> _ensureUser(
  SupabaseClient admin, {
  required String email,
  required String password,
}) async {
  try {
    final res = await admin.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    if (res.user != null) return res.user!.id;
  } catch (e) {
    // Expected if user already exists
  }

  // Fallback: fetch existing user
  final users = await admin.auth.admin.listUsers();
  final existing = users.firstWhere(
    (u) => u.email == email,
    orElse: () =>
        throw StateError('_ensureUser: failed to create or find $email'),
  );
  return existing.id;
}

/// Deletes a Supabase Auth user by [userId] via the Admin API.
Future<void> _deleteUser(String userId, SupabaseClient? admin) async {
  if (admin == null) return;
  try {
    await admin.auth.admin.deleteUser(userId);
  } catch (e) {
    // ignore: avoid_print
    print('[tearDownAll] Warning: failed to delete user $userId: $e');
  }
}

Future<void> _ensureOrg(
  SupabaseClient admin, {
  required String id,
  required String name,
}) async {
  final randomCnpj = DateTime.now()
      .toUtc()
      .microsecondsSinceEpoch
      .toString()
      .substring(0, 14);
  await admin.from('organizations').upsert({
    'id': id,
    'name': name,
    'cnpj': randomCnpj,
  }, onConflict: 'id');
}

Future<void> _assignRole(
  SupabaseClient admin, {
  required String userId,
  required String orgId,
  required String role,
}) async {
  await admin.from('user_roles').upsert({
    'user_id': userId,
    'organization_id': orgId,
    'role': role,
  }, onConflict: 'user_id');
}

Future<SupabaseClient> _signIn(String email, String password) async {
  final client = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.supabaseAnonKey,
  );

  AuthApiException? lastError;
  for (int i = 0; i < 5; i++) {
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      return client;
    } on AuthApiException catch (e) {
      lastError = e;
      if (e.code == 'invalid_credentials') {
        // Wait and retry - potential race in local Supabase propagation
        await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
        continue;
      }
      rethrow;
    }
  }
  throw lastError!;
}
