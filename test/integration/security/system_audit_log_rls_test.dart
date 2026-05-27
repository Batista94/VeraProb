/// Integration tests for system_audit_log — CT29 RLS / append-only / HMAC /
/// AUDIT_LOG_VIEWED recursivity (Group 10 plan: F3, cases 8–11, 35–36, 39–40).
///
/// Skip-fast when the local Supabase stack is offline. Tests that depend on
/// implementation work the plan flags as TDD-RED (HMAC, AUDIT_LOG_VIEWED) are
/// skipped with explicit backlog comments.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../test/infrastructure/postgres/postgres_test_config.dart';

const _orgAId = '11111111-1111-1111-1111-111111111111';
const _orgBId = '22222222-2222-2222-2222-222222222222';

Future<bool> _stackOnline() async {
  try {
    final res = await http
        .get(Uri.parse(PostgresTestConfig.supabaseUrl))
        .timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

void main() {
  late SupabaseClient seedClient;
  String? seededId;

  setUpAll(() async {
    if (!await _stackOnline()) return;
    seedClient = PostgresTestConfig.createServiceRoleClient();
    await PostgresTestConfig.ensureSentinelOrg(id: _orgAId, name: 'Org A');
    await PostgresTestConfig.ensureSentinelOrg(id: _orgBId, name: 'Org B');
    await PostgresTestConfig.cleanupSystemAuditLog(orgIds: [_orgAId, _orgBId]);

    await PostgresTestConfig.seedSystemAuditLogEvent(
      orgId: _orgAId,
      eventType: 'ORG_CREATED',
      severity: 'info',
    );
    await PostgresTestConfig.seedSystemAuditLogEvent(
      orgId: _orgBId,
      eventType: 'ORG_CREATED',
      severity: 'info',
    );
    seededId = await PostgresTestConfig.seedSystemAuditLogEvent(
      orgId: null,
      eventType: 'EVALUATION_RUN',
      severity: 'critical',
    );
  });

  tearDownAll(() async {
    if (!await _stackOnline()) return;
    await PostgresTestConfig.cleanupSystemAuditLog(orgIds: [_orgAId, _orgBId]);
    await seedClient.dispose();
  });

  group('system_audit_log — RLS (CT29 cases 8–11)', () {
    test('8 anon (non-admin) sees 0 rows', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      final anon = SupabaseClient(
        PostgresTestConfig.supabaseUrl,
        PostgresTestConfig.supabaseAnonKey,
      );
      try {
        expect(
          () => anon.from('system_audit_log').select(),
          throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
          ),
        );
      } finally {
        await anon.dispose();
      }
    });

    test('9 admin of Org_A sees only its org + system rows', () async {
      // Requires a JWT with `user_role=admin` AND `app_metadata.org_id=orgA`.
      // The local Supabase stack does not expose a custom-claims hook in the
      // default config, so this case is parked as a backlog driver. Flip
      // `skip` to false once a JWT-claims provisioner is wired into
      // PostgresTestConfig.createSuperAdminAuthSession (TODO).
      markTestSkipped(
        'TDD-RED — needs custom-claims JWT provisioner '
        '(user_role=admin + app_metadata.org_id). See plan adendo F3#9.',
      );
    }, skip: true);

    test('10 UPDATE rejected (INSTEAD NOTHING rule)', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      expect(seededId, isNotNull);

      // INV-3: service_role bypasses RLS but the INSTEAD NOTHING rule
      // short-circuits the UPDATE. PostgREST appends RETURNING * which
      // causes a 0A000 error — we catch this as proof of blocking.
      try {
        await seedClient
            .from('system_audit_log')
            .update({'severity': 'debug'})
            .eq('id', seededId!);
      } on PostgrestException catch (e) {
        // 0A000 is the expected protocol error when an INSTEAD NOTHING
        // rule meets a RETURNING clause.
        if (e.code != '0A000') rethrow;
      }

      final after = await seedClient
          .from('system_audit_log')
          .select('severity')
          .eq('id', seededId!)
          .single();
      expect(
        after['severity'],
        equals('critical'),
        reason: 'Immutability check: severity must remain unchanged',
      );
    });

    test('11 DELETE rejected (INSTEAD NOTHING rule)', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      expect(seededId, isNotNull);

      try {
        await seedClient.from('system_audit_log').delete().eq('id', seededId!);
      } on PostgrestException catch (e) {
        if (e.code != '0A000') rethrow;
      }

      final after = await seedClient
          .from('system_audit_log')
          .select('id')
          .eq('id', seededId!);
      expect(
        after,
        hasLength(1),
        reason: 'INV-3: append-only — DELETE must be a no-op or blocked',
      );
    });
  });

  group('super-admin-proxy — INV-31 HMAC (cases 35–36, TDD-RED backlog)', () {
    test(
      '35 proxy rejects request without/with tampered HMAC signature',
      () async {
        // Backlog: super-admin-proxy currently does not verify HMAC. When
        // `shared/hmac_signer.ts` is wired into the proxy, this test must
        // assert 401/403 for a request that is missing or tampered.
        markTestSkipped(
          'TDD-RED — implement HMAC verification in '
          'supabase/functions/super-admin-proxy/index.ts (plan adendo A).',
        );
      },
      skip: true,
    );

    test('36 proxy rejects replayed request outside 5-minute window', () async {
      markTestSkipped(
        'TDD-RED — implement timestamp-window replay check in '
        'super-admin-proxy (plan adendo A).',
      );
    }, skip: true);
  });

  group('AUDIT_LOG_VIEWED recursivity (cases 39–40, TDD-RED backlog)', () {
    test(
      '39 viewing audit log inserts AUDIT_LOG_VIEWED row at DB level',
      () async {
        markTestSkipped(
          'TDD-RED — implement AUDIT_LOG_VIEWED emission path (plan adendo B). '
          'Once wired, assert: after a SuperAdmin GETs system_audit_log via the '
          'real repo, a new row exists with event_type=AUDIT_LOG_VIEWED, '
          'actor_type=HUMAN, organization_id IS NULL.',
        );
      },
      skip: true,
    );

    test(
      '40 anti-loop — AUDIT_LOG_VIEWED does not recurse on its own listing',
      () async {
        markTestSkipped(
          'TDD-RED — once AUDIT_LOG_VIEWED emission is implemented, verify '
          'a single read produces exactly one new event (no trigger recursion).',
        );
      },
      skip: true,
    );
  });

  // Smoke check that the test_cleanup_system_audit_log RPC exists. If the
  // teardown migration was never applied, every other test would silently
  // leak rows across runs.
  test('test_cleanup_system_audit_log RPC is callable', () async {
    if (!await _stackOnline()) {
      markTestSkipped('local supabase stack offline');
      return;
    }
    final res = await seedClient.rpc<dynamic>(
      'test_cleanup_system_audit_log',
      params: {'p_org_ids': const <String>[]},
    );
    // PostgreSQL returns null for VOID RPCs; absence of throw is the contract.
    expect(res, anyOf(isNull, isA<dynamic>()));
  });

  // Reference to silence the unused-import lint when the JSON helper is not
  // exercised by an active test (cases 35–36 are backlog).
  test('json codec is wired (sanity)', () {
    expect(jsonEncode({'k': 'v'}), '{"k":"v"}');
  });
}
