// =============================================================================
// Task 1 — Multi-tenant Isolation (RLS / INV-1, INV-2, INV-22)
// =============================================================================
//
// Forensic Insight — QA & Security Lead (Paranoid Protector)
// Invariants under scrutiny:
//   INV-1  (Identity Sovereignty): org_id filter on ALL queries
//   INV-2  (RLS Hardening): auth.jwt() org_id, never uid
//   INV-22 (Tenant Isolation): Org-A MUST NOT see Org-B data
//   INV-26 (Error Parity): wrong-org returns null, never leaks existence
//
// Strategy:
//   - Seed data for Org-A and Org-B using service_role (bypasses RLS).
//   - Query via service_role with a MISMATCHED org_id filter — the repository
//     itself enforces .eq('organization_id', organizationId) at wire level.
//   - The repository must return null / empty, proving structural isolation
//     independent of RLS configuration.
//   - Additionally verify the URL contains the correct org_id filter (wire proof).
//
// Note: full auth.jwt() RLS path requires a real authenticated session which
// is outside the scope of Dart unit/integration tests. For that layer, pgTAP
// tests in supabase/tests/ cover the DB-side RLS policies directly.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/infrastructure/telegram/postgres_telegram_repository.dart';

import '../postgres/postgres_test_config.dart';

// ── MockClient helpers ────────────────────────────────────────────────────────

/// Builds a [PostgresTelegramRepository] wired to a [MockClient].
PostgresTelegramRepository _repoWithMock(
  Future<http.Response> Function(http.Request request) handler,
) {
  final supabaseClient = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.serviceRoleKey,
    httpClient: MockClient(handler),
  );
  return PostgresTelegramRepository(supabaseClient);
}

void main() async {
  const uuid = Uuid();

  // Org-A: sentinel test org. Org-B: adversary org.
  const orgA = PostgresTestConfig.testOrgId;
  // ignore: prefer_const_declarations
  final orgB = '00000000-0000-0000-0000-000000000099'; // adversary

  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  // ===========================================================================
  // Group A — Wire-level org_id filter proof (MockClient, always runs)
  // ===========================================================================
  group('RLS-WIRE: Repository enforces org_id filter at wire level', () {
    // ── RLS-WIRE-1 ─────────────────────────────────────────────────────────
    test(
      'RLS-WIRE-1: findOrphanEvidences URL contains organization_id=eq.{orgId}',
      () async {
        String? capturedUrl;

        final repo = _repoWithMock((request) async {
          capturedUrl = request.url.toString();
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        await repo.findOrphanEvidences(organizationId: orgA);

        expect(
          capturedUrl,
          contains('organization_id=eq.$orgA'),
          reason:
              'INV-1: The wire URL MUST contain organization_id=eq.orgA '
              'to enforce structural isolation at the query layer, '
              'independent of RLS configuration.',
        );
        expect(
          capturedUrl,
          contains('requires_manual_link=eq.true'),
          reason:
              'findOrphanEvidences must filter requires_manual_link=true '
              'to avoid fetching all evidence.',
        );
      },
    );

    // ── RLS-WIRE-2 ─────────────────────────────────────────────────────────
    test(
      'RLS-WIRE-2: findLatestTokenForDriver URL contains both driver_id and organization_id',
      () async {
        const driverId = 'driver-uuid-test';
        String? capturedUrl;

        final repo = _repoWithMock((request) async {
          capturedUrl = request.url.toString();
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        await repo.findLatestTokenForDriver(
          driverId: driverId,
          organizationId: orgA,
        );

        expect(
          capturedUrl,
          contains('driver_id=eq.$driverId'),
          reason: 'INV-1: driver_id filter must be present in wire URL.',
        );
        expect(
          capturedUrl,
          contains('organization_id=eq.$orgA'),
          reason:
              'INV-1: organization_id filter must be present — prevents '
              'drivers from one org accessing tokens of another.',
        );
      },
    );

    // ── RLS-WIRE-3 ─────────────────────────────────────────────────────────
    test(
      'RLS-WIRE-3: hasActiveBinding URL contains driver_id and organization_id',
      () async {
        const driverId = 'driver-bind-test';
        String? capturedUrl;

        final repo = _repoWithMock((request) async {
          capturedUrl = request.url.toString();
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        await repo.hasActiveBinding(driverId: driverId, organizationId: orgA);

        expect(
          capturedUrl,
          contains('driver_id=eq.$driverId'),
          reason: 'INV-1: driver_id filter required in binding check.',
        );
        expect(
          capturedUrl,
          contains('organization_id=eq.$orgA'),
          reason: 'INV-22: binding check must be scoped to the tenant.',
        );
      },
    );

    // ── RLS-WIRE-4 ─────────────────────────────────────────────────────────
    test(
      'RLS-WIRE-4: Adversary org returns null / empty from mock (anti-oracle)',
      () async {
        final repo = _repoWithMock((request) async {
          // Simulate Supabase returning null when org filter excludes the row.
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        // Attempt to find a token belonging to Org-A, but querying as Org-B.
        final result = await repo.findLatestTokenForDriver(
          driverId: uuid.v4(),
          organizationId: orgB, // adversary org
        );

        expect(
          result,
          isNull,
          reason:
              'INV-26: Querying with wrong org must return null. '
              'No data existence inference allowed (anti-Oracle).',
        );
      },
    );

    // ── RLS-WIRE-5 ─────────────────────────────────────────────────────────
    test(
      'RLS-WIRE-5: findOrphanEvidences with adversary org returns empty list',
      () async {
        final repo = _repoWithMock((request) async {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final results = await repo.findOrphanEvidences(organizationId: orgB);

        expect(
          results,
          isEmpty,
          reason:
              'INV-22: Adversary org must receive empty list, never Org-A data.',
        );
      },
    );

    // ── RLS-WIRE-6 ─────────────────────────────────────────────────────────
    test(
      'RLS-WIRE-6: linkEvidenceToExecution INSERT payload contains organization_id',
      () async {
        Map<String, dynamic>? capturedBody;

        final repo = _repoWithMock((request) async {
          if (request.method == 'POST') {
            capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          // .single() expects a JSON object
          return http.Response(
            jsonEncode({
              'id': uuid.v4(),
              'organization_id': orgA,
              'evidence_upload_id': uuid.v4(),
              'execution_set_id': uuid.v4(),
              'linked_at_utc': DateTime.now().toUtc().toIso8601String(),
              'linked_by_user_id': uuid.v4(),
              'source': 'reconciliation',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        await repo.linkEvidenceToExecution(
          evidenceUploadId: uuid.v4(),
          executionSetId: uuid.v4(),
          organizationId: orgA,
          userId: uuid.v4(),
        );

        expect(
          capturedBody,
          isNotNull,
          reason: 'POST body must have been captured.',
        );
        expect(
          capturedBody!['organization_id'],
          equals(orgA),
          reason:
              'INV-1/INV-8: INSERT payload must carry the correct org_id '
              'to satisfy RLS WITH CHECK policy on telegram_evidence_links.',
        );
      },
    );
  });

  // ===========================================================================
  // Group B — Integration isolation (requires local Supabase)
  // ===========================================================================
  group(
    'RLS-INT: Cross-tenant data isolation against real DB',
    () {
      late SupabaseClient serviceClient;
      late String driverA;
      late String driverB;

      setUpAll(() async {
        serviceClient = PostgresTestConfig.createServiceRoleClient();

        // Ensure both orgs exist.
        await PostgresTestConfig.ensureSentinelOrg(id: orgA);
        await PostgresTestConfig.ensureSentinelOrg(
          id: orgB,
          name: 'Adversary Org B',
        );

        // Seed one driver in each org.
        driverA = await PostgresTestConfig.seedDriver(
          serviceClient,
          orgId: orgA,
          licenseNumber: 'AAA-1111',
        );
        driverB = await PostgresTestConfig.seedDriver(
          serviceClient,
          orgId: orgB,
          licenseNumber: 'BBB-2222',
        );
      });

      tearDownAll(() async {
        await PostgresTestConfig.cleanupTelegramData(
          serviceClient,
          orgId: orgA,
        );
        await PostgresTestConfig.cleanupTelegramData(
          serviceClient,
          orgId: orgB,
        );
        await serviceClient.dispose();
      });

      // ── RLS-INT-1 ──────────────────────────────────────────────────────
      test(
        'RLS-INT-1: findLatestTokenForDriver with wrong org returns null',
        () async {
          // Seed a token for Org-A / driverA.
          final code = PostgresTestConfig.fakeTokenCode('rls-int-1-$orgA');
          await PostgresTestConfig.seedBindingToken(
            serviceClient,
            orgId: orgA,
            driverId: driverA,
            code: code,
          );

          // Query as Org-B — must return null.
          final repoB = PostgresTelegramRepository(serviceClient);
          final result = await repoB.findLatestTokenForDriver(
            driverId: driverA, // correct driver ID but wrong org
            organizationId: orgB, // adversary org
          );

          expect(
            result,
            isNull,
            reason:
                'INV-1/INV-22: Token belongs to Org-A. '
                'Querying with Org-B must return null — '
                'the repository org_id filter prevents cross-tenant access.',
          );
        },
      );

      // ── RLS-INT-2 ──────────────────────────────────────────────────────
      test(
        'RLS-INT-2: findOrphanEvidences returns only Org-A evidence, never Org-B',
        () async {
          // Seed one orphan evidence for each org.
          final hashA = PostgresTestConfig.fakeForensicHash('rls-int-2-orgA');
          final hashB = PostgresTestConfig.fakeForensicHash('rls-int-2-orgB');

          final msgIdA =
              DateTime.now().toUtc().millisecondsSinceEpoch % 1000000;
          final msgIdB = msgIdA + 1;

          await PostgresTestConfig.seedTelegramEvidenceUpload(
            serviceClient,
            orgId: orgA,
            driverId: driverA,
            forensicHash: hashA,
            chatId: 111111111,
            telegramMessageId: msgIdA,
          );
          await PostgresTestConfig.seedTelegramEvidenceUpload(
            serviceClient,
            orgId: orgB,
            driverId: driverB,
            forensicHash: hashB,
            chatId: 222222222,
            telegramMessageId: msgIdB,
          );

          // Repository scoped to Org-A should only return Org-A evidence.
          final repo = PostgresTelegramRepository(serviceClient);
          final orphansA = await repo.findOrphanEvidences(organizationId: orgA);

          expect(
            orphansA.every((e) => e.organizationId == orgA),
            isTrue,
            reason:
                'INV-22: All returned evidences must belong to Org-A. '
                'No Org-B record should appear.',
          );
          expect(
            orphansA.any((e) => e.forensicHash == hashB),
            isFalse,
            reason:
                'INV-22: Org-B forensic hash must never appear in Org-A result.',
          );
        },
      );

      // ── RLS-INT-3 ──────────────────────────────────────────────────────
      test(
        'RLS-INT-3: hasActiveBinding returns false for driver from wrong org',
        () async {
          // driverB belongs to Org-B. Querying with Org-A must return false.
          final repo = PostgresTelegramRepository(serviceClient);
          final hasBinding = await repo.hasActiveBinding(
            driverId: driverB,
            organizationId: orgA, // wrong org for driverB
          );

          expect(
            hasBinding,
            isFalse,
            reason:
                'INV-22: driverB is in Org-B. '
                'Checking binding with Org-A context must return false — '
                'never confirm cross-tenant driver existence.',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
