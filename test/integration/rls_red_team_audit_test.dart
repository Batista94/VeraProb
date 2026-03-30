// Expanded RLS Sovereignty Red Team Audit — INV-1 & INV-20
//
// Validates strict multi-tenant isolation, partitioned ledger sovereignty,
// and PII masking (LGPD) across all sensitive tables and views.
//
// PREREQUISITES: `supabase start` running locally.
// RUN: flutter test test/integration/rls_red_team_audit_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();

// Stabilized Sentinel IDs for the Red Team session
const _orgAId = '00000000-1111-0000-0000-000000000001';
const _orgBId = '00000000-2222-0000-0000-000000000001';
const _userAEmail = 'redteam_admin_a@veraprob.test';
const _userBEmail = 'redteam_admin_b@veraprob.test';
const _operatorEmail = 'redteam_operator_a@veraprob.test';
const _testPassword = 'RedTeamPassword123!';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'RLS Sovereignty Audit (Red Team Expansion)',
    skip: !isRunning ? 'Supabase local instance not detected' : null,
    () {
      late SupabaseClient adminClient;
      late SupabaseClient tenantAClient;
      late SupabaseClient tenantBClient;
      late SupabaseClient operatorClient;

      setUpAll(() async {
        adminClient = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );

        // ── Step 1: Provision Multi-Tenant Infrastructure ───────────────────
        await _ensureOrg(
          adminClient,
          id: _orgAId,
          name: 'RedTeam — Target Alpha',
        );
        await _ensureOrg(
          adminClient,
          id: _orgBId,
          name: 'RedTeam — Target Beta',
        );

        final userAId = await _ensureUser(
          adminClient,
          email: _userAEmail,
          password: _testPassword,
        );
        final userBId = await _ensureUser(
          adminClient,
          email: _userBEmail,
          password: _testPassword,
        );
        final operatorId = await _ensureUser(
          adminClient,
          email: _operatorEmail,
          password: _testPassword,
        );

        await _assignRole(
          adminClient,
          userId: userAId,
          orgId: _orgAId,
          role: 'TENANT_ADMIN',
        );
        await _assignRole(
          adminClient,
          userId: userBId,
          orgId: _orgBId,
          role: 'TENANT_ADMIN',
        );
        await _assignRole(
          adminClient,
          userId: operatorId,
          orgId: _orgAId,
          role: 'OPERATOR',
        );

        // ── Step 2: Seed Sensitive Forensic Data (Target Beta) ──────────────
        // We seed data in Org B that Org A should NEVER be able to see.
        final contractBId = _uuid.v4();
        await adminClient.from('contracts').upsert({
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
        await adminClient.from('sla_audit_ledger_v2').insert({
          'organization_id': _orgBId,
          'type': 'SENSITIVE_PAYMENT_CLOSE',
          'contract_id': contractBId,
          'plan_version': 1,
          'operator_id': userBId,
          'payload': {'secret_fines_cents': 999999},
          'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
        });

        // Evaluation Traces
        await adminClient.from('contractual_evaluation_traces').insert({
          'organization_id': _orgBId,
          'entity_id': 'SET-SECRET-001',
          'triggering_event_id': _uuid.v4(),
          'evaluated_at_utc': DateTime.now().toUtc().toIso8601String(),
          'engine_version': 'veraprob-core_v3',
          'decisions_jsonb': [
            {
              'outcome': 'SANCTION_RECOMMENDED',
              'reason': 'Late Arrival Breach',
            },
          ],
        });

        // Operational Alerts
        await adminClient.from('operational_alerts').insert({
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

        // ── Step 3: Login to Tenants ───────────────────────────────────────
        tenantAClient = await _signIn(_userAEmail, _testPassword);
        tenantBClient = await _signIn(_userBEmail, _testPassword);
        operatorClient = await _signIn(_operatorEmail, _testPassword);
      });

      // ── Sanity Check ────────────────────────────────────────────────────────
      test(
        'SANITY — Availability: Tenant B can see their own ledger',
        () async {
          final res = await tenantBClient
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
        final session = tenantAClient.auth.currentSession;
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
          final res = await tenantAClient
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
          final res = await tenantAClient
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
          final res = await tenantAClient
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
          // Seed a contractor with real PII via admin
          final contractorId = _uuid.v4();
          await adminClient.from('contractors').upsert({
            'id': contractorId,
            'organization_id': _orgAId,
            'name': 'PII Test Contractor',
            'tax_id': '12345678000199', // CNPJ
            'primary_email': 'legit_owner@business.com',
            'cnpj': '12345678000199',
          });

          final res = await operatorClient
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
          final res = await tenantAClient
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
            () async => tenantAClient.from('sla_audit_ledger_v2').insert({
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
          await adminClient.from('sla_audit_ledger_v2').insert({
            'id': ledgerId,
            'organization_id': _orgAId,
            'type': 'IMMUTABILITY_PROBE',
            'contract_id': _uuid.v4(),
            'plan_version': 1,
            'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
          });

          await expectLater(
            () async => adminClient
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

Future<String> _ensureUser(
  SupabaseClient admin, {
  required String email,
  required String password,
}) async {
  final res = await http.post(
    Uri.parse('${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users'),
    headers: {
      'apikey': PostgresTestConfig.serviceRoleKey,
      'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
    }),
  );

  if (res.statusCode == 200 || res.statusCode == 201) {
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }

  // Fallback to fetch existing
  final listRes = await http.get(
    Uri.parse(
      '${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users?email=$email',
    ),
    headers: {
      'apikey': PostgresTestConfig.serviceRoleKey,
      'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
    },
  );
  final users =
      (jsonDecode(listRes.body) as Map<String, dynamic>)['users'] as List;
  return users.first['id'] as String;
}

Future<void> _ensureOrg(
  SupabaseClient admin, {
  required String id,
  required String name,
}) async {
  await admin.from('organizations').upsert({
    'id': id,
    'name': name,
    'cnpj': id.replaceAll('-', '').substring(0, 14),
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
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}
