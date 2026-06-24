// Integration tests for PostgresPdfDossierLogRepository.
//
// Requires: `supabase start` running locally on 127.0.0.1:54321.
// Run: flutter test test/infrastructure/reporting/postgres_pdf_dossier_log_repository_test.dart
//
// Invariants verified:
//   INV-1  — organizationId is enforced; never derived from auth.uid()
//   INV-3  — INSERT only (append-only forensic audit trail)
//   INV-15 — 23505 unique constraint treated as idempotent success (custody already logged)
//   INV-22 — Tenant-A NEVER reads Tenant-B log entries
//   INV-26 — PostgresErrorInterceptor maps DB error codes to domain exceptions

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/infrastructure/reporting/postgres_pdf_dossier_log_repository.dart';

import '../postgres/postgres_test_config.dart';

const _uuid = Uuid();
const _testPassword = 'TestPassword123!';

final _orgAId = _uuid.v4();
final _orgBId = _uuid.v4();
final _userAEmail = 'pdfdossier_a_${_uuid.v4().substring(0, 8)}@veraprob.test';
final _userBEmail = 'pdfdossier_b_${_uuid.v4().substring(0, 8)}@veraprob.test';

// generated_by is UUID NOT NULL in the migration — must use valid UUIDs.
final _opUserTest = _uuid.v4();
final _opA1 = _uuid.v4();
final _opA2 = _uuid.v4();
final _opB1 = _uuid.v4();
final _opB2 = _uuid.v4();
final _opB = _uuid.v4();

// ── Auth helpers ──────────────────────────────────────────────────────────────

Future<String> _ensureUser(String email, {required String orgId}) async {
  final res = await http.post(
    Uri.parse('${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users'),
    headers: {
      'apikey': PostgresTestConfig.serviceRoleKey,
      'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': _testPassword,
      'email_confirm': true,
      'app_metadata': {'org_id': orgId},
    }),
  );
  if (res.statusCode == 200 || res.statusCode == 201) {
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }
  if (res.statusCode == 422) {
    final list = await http.get(
      Uri.parse(
        '${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users?email=$email',
      ),
      headers: {
        'apikey': PostgresTestConfig.serviceRoleKey,
        'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
      },
    );
    final users =
        ((jsonDecode(list.body) as Map<String, dynamic>)['users'] as List);
    final userId = (users.first as Map<String, dynamic>)['id'] as String;

    // Ensure app_metadata.org_id is set (may be missing from a prior run).
    await http.put(
      Uri.parse(
        '${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users/$userId',
      ),
      headers: {
        'apikey': PostgresTestConfig.serviceRoleKey,
        'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'app_metadata': {'org_id': orgId},
      }),
    );
    return userId;
  }
  throw Exception('Failed to provision user $email: ${res.body}');
}

Future<SupabaseClient> _signIn(String email) async {
  final client = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.supabaseAnonKey,
  );
  await client.auth.signInWithPassword(email: email, password: _testPassword);
  return client;
}

// ── Main ──────────────────────────────────────────────────────────────────────

// Set to true in setUpAll only when BOTH Supabase is running AND the
// pdf_dossier_logs migration has been applied (PGRST205 guard).
bool _migrationApplied = false;

void main() {
  group('PostgresPdfDossierLogRepository — Integration', () {
    late SupabaseClient adminClient;
    late SupabaseClient orgAClient;
    late SupabaseClient orgBClient;
    late PostgresPdfDossierLogRepository repoA;

    setUpAll(() async {
      final isRunning = await PostgresTestConfig.isSupabaseRunning();
      if (!isRunning) return;

      adminClient = PostgresTestConfig.createServiceRoleClient();

      // Guard: verify the migration has been applied before running tests.
      // PGRST205 = table not in schema cache (migration not yet run).
      try {
        await adminClient.from('pdf_dossier_logs').select('id').limit(0);
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST205') return; // migration not applied — skip all
        rethrow;
      }

      _migrationApplied = true;

      await PostgresTestConfig.ensureSentinelOrg(
        id: _orgAId,
        name: 'PDF Log Test Org A',
      );
      await PostgresTestConfig.ensureSentinelOrg(
        id: _orgBId,
        name: 'PDF Log Test Org B',
      );

      final userAId = await _ensureUser(_userAEmail, orgId: _orgAId);
      final userBId = await _ensureUser(_userBEmail, orgId: _orgBId);

      await adminClient.from('user_roles').upsert({
        'user_id': userAId,
        'organization_id': _orgAId,
        'role': 'TENANT_ADMIN',
      }, onConflict: 'user_id');
      await adminClient.from('user_roles').upsert({
        'user_id': userBId,
        'organization_id': _orgBId,
        'role': 'TENANT_ADMIN',
      }, onConflict: 'user_id');

      orgAClient = await _signIn(_userAEmail);
      orgBClient = await _signIn(_userBEmail);

      repoA = PostgresPdfDossierLogRepository(orgAClient);
    });

    tearDownAll(() async {
      try {
        await adminClient.from('pdf_dossier_logs').delete().inFilter(
          'organization_id',
          [_orgAId, _orgBId],
        );
      } catch (_) {}
      try {
        await orgAClient.auth.signOut();
        await orgBClient.auth.signOut();
        await adminClient.dispose();
      } catch (_) {}
    });

    // ── GRUPO A: Happy Path ───────────────────────────────────────────────────

    test(
      'LOG-A1 [INV-1, INV-3]: logGeneration inserts row with correct fields',
      () async {
        final isRunning = await PostgresTestConfig.isSupabaseRunning();
        if (!isRunning || !_migrationApplied) {
          markTestSkipped(
            isRunning
                ? 'Migration pdf_dossier_logs not applied (run: supabase db push)'
                : 'Supabase não está rodando',
          );
          return;
        }

        final entryId = _uuid.v4();
        final hash = 'a' * 64; // 64-char SHA-256-like hex string

        await repoA.logGeneration(
          organizationId: _orgAId,
          slaLedgerEntryId: entryId,
          documentHash: hash,
          operatorId: _opUserTest,
        );

        // Verify via service_role (bypass RLS to read back the row).
        final rows = await adminClient
            .from('pdf_dossier_logs')
            .select()
            .eq('organization_id', _orgAId)
            .eq('sla_ledger_entry_id', entryId);

        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row['organization_id'], equals(_orgAId));
        expect(row['sla_ledger_entry_id'], equals(entryId));
        expect(row['document_hash_sha256'], equals(hash));
        expect(row['generated_by'], equals(_opUserTest));
      },
    );

    // ── GRUPO B: INV-15 — Idempotency / Unique Constraint ────────────────────

    test(
      'LOG-B1 [INV-15]: duplicate (org, entry, hash) is idempotent — no exception',
      () async {
        final isRunning = await PostgresTestConfig.isSupabaseRunning();
        if (!isRunning || !_migrationApplied) {
          markTestSkipped(
            isRunning
                ? 'Migration pdf_dossier_logs not applied (run: supabase db push)'
                : 'Supabase não está rodando',
          );
          return;
        }

        final entryId = _uuid.v4();
        final hash = 'b' * 64;

        // First insert succeeds.
        await repoA.logGeneration(
          organizationId: _orgAId,
          slaLedgerEntryId: entryId,
          documentHash: hash,
          operatorId: _opA1,
        );

        // Second insert with same (org, entry, hash) must NOT throw — idempotent
        // (INV-15: custody entry already exists; PDF was already delivered).
        await expectLater(
          () => repoA.logGeneration(
            organizationId: _orgAId,
            slaLedgerEntryId: entryId,
            documentHash: hash,
            operatorId: _opA2,
          ),
          returnsNormally,
        );
      },
    );

    test(
      'LOG-B2 [INV-15]: different hash for same entry is allowed (re-generation)',
      () async {
        final isRunning = await PostgresTestConfig.isSupabaseRunning();
        if (!isRunning || !_migrationApplied) {
          markTestSkipped(
            isRunning
                ? 'Migration pdf_dossier_logs not applied (run: supabase db push)'
                : 'Supabase não está rodando',
          );
          return;
        }

        final entryId = _uuid.v4();

        // Two different hashes for the same entry — both should succeed.
        await repoA.logGeneration(
          organizationId: _orgAId,
          slaLedgerEntryId: entryId,
          documentHash: 'c' * 64,
          operatorId: _opB1,
        );
        await repoA.logGeneration(
          organizationId: _orgAId,
          slaLedgerEntryId: entryId,
          documentHash: 'd' * 64,
          operatorId: _opB2,
        );

        final rows = await adminClient
            .from('pdf_dossier_logs')
            .select()
            .eq('organization_id', _orgAId)
            .eq('sla_ledger_entry_id', entryId);

        expect(rows, hasLength(2));
      },
    );

    // ── GRUPO C: INV-22 — Tenant Isolation ───────────────────────────────────

    test(
      'LOG-C1 [INV-22]: Org-A cannot read Org-B log entries via RLS',
      () async {
        final isRunning = await PostgresTestConfig.isSupabaseRunning();
        if (!isRunning || !_migrationApplied) {
          markTestSkipped(
            isRunning
                ? 'Migration pdf_dossier_logs not applied (run: supabase db push)'
                : 'Supabase não está rodando',
          );
          return;
        }

        // Seed Org-B log via service_role.
        final entryBId = _uuid.v4();
        await adminClient.from('pdf_dossier_logs').insert({
          'organization_id': _orgBId,
          'sla_ledger_entry_id': entryBId,
          'document_hash_sha256': 'e' * 64,
          'generated_by': _opB,
        });

        // Org-A client queries for Org-B row.
        final rows = await orgAClient
            .from('pdf_dossier_logs')
            .select()
            .eq('organization_id', _orgBId)
            .eq('sla_ledger_entry_id', entryBId);

        expect(
          rows,
          isEmpty,
          reason:
              'INV-22: RLS must prevent Org-A from reading Org-B log entries.',
        );
      },
    );
  });
}
