import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_test_config.dart';

/// Property-Based Test: Integridade da Cascata de Arquivamento
///
/// **Validates: Requirements 4.3, 9.1, 9.5**
///
/// Feature: superadmin-org-management-e2e-tests, Property 1: Integridade da Cascata de Arquivamento
///
/// For any organization with N active administrators (1 ≤ N ≤ 10), when the
/// archive operation is executed, ALL N administrators must have:
///   - `is_active = false` in `user_roles`
///   - `banned_until = 'infinity'` in `auth.users`
///
/// The count of blocked users must equal exactly N.
///
/// Formal predicate:
/// ```
/// ∀ org ∈ Sistema:
///   org.status = 'ARCHIVED' →
///     (∀ admin ∈ org.admins:
///       admin.is_active = false ∧ admin.banned_until = 'infinity')
/// ```
///
/// This test runs WITHOUT UI — it exercises the archive cascade directly
/// via the `super_admin_archive_organization` RPC using service_role.
///
/// Minimum 100 iterations.
void main() {
  late SupabaseClient serviceRoleClient;
  bool supabaseAvailable = false;

  group('Feature: superadmin-org-management-e2e-tests, '
      'Property 1: Integridade da Cascata de Arquivamento', () {
    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;
      serviceRoleClient = SuperAdminTestConfig.createServiceRoleClient();
    });

    tearDownAll(() async {
      if (!supabaseAvailable) return;
      await serviceRoleClient.dispose();
    });

    // ── Pre-generate 100+ inputs using Glados generators ──────────────────
    // Glados.test uses package:test's `test` (not testWidgets), but since
    // this is a DB-only property test (no UI), we pre-generate values and
    // iterate with standard `test()` to ensure minimum 100 iterations.
    final random = Random(42);
    final numAdminsGen = any.intInRange(1, 11); // 1..10 inclusive
    const iterations = 100;

    final adminCounts = List.generate(
      iterations,
      (i) => numAdminsGen(random, i + 5).value,
    );

    for (var i = 0; i < iterations; i++) {
      final numAdmins = adminCounts[i];

      test(
        'iter $i: Arquivar org com $numAdmins admins bloqueia todos',
        () async {
          // `skip:` is evaluated at collection time, before setUpAll sets
          // supabaseAvailable — guard at runtime instead so the flag is read
          // after the probe has actually run.
          if (!supabaseAvailable) {
            markTestSkipped(
              'Supabase local não disponível. Execute: supabase start',
            );
            return;
          }
          // 1. Create org with N active admins
          final org = await SuperAdminDataFactory.createOrgWithAdmins(
            orgName: 'PBT-Archive-Cascade-$i',
            cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
            activeAdmins: numAdmins,
            pendingAdmins: 0,
          );

          try {
            // 2. Execute archive via RPC (service_role bypasses JWT check)
            await serviceRoleClient.rpc<dynamic>(
              'super_admin_archive_organization',
              params: {
                'p_org_id': org.orgId,
                'p_reason': 'PBT cascata iter $i — $numAdmins admins',
                'p_super_admin_id': org.admins.first.userId,
              },
            );

            // 3. Verify org status is ARCHIVED
            final status = await SuperAdminDbVerifier.getOrgStatus(
              org.orgId,
              client: serviceRoleClient,
            );
            expect(
              status,
              equals('ARCHIVED'),
              reason:
                  'Org status deve ser ARCHIVED após arquivamento '
                  '(iter $i, N=$numAdmins)',
            );

            // 4. Verify ALL admins have is_active=false
            await SuperAdminDbVerifier.assertAllUsersActiveStatus(
              orgId: org.orgId,
              expectedActive: false,
              client: serviceRoleClient,
            );

            // 5. Verify ALL admins have banned_until='infinity'
            await SuperAdminDbVerifier.assertAllUsersBannedStatus(
              orgId: org.orgId,
              shouldBeBanned: true,
              client: serviceRoleClient,
            );

            // 6. Verify count of blocked users == N
            final blockedCount = await SuperAdminDbVerifier.countBlockedUsers(
              org.orgId,
              client: serviceRoleClient,
            );
            expect(
              blockedCount,
              equals(numAdmins),
              reason:
                  'Número de admins bloqueados ($blockedCount) deve ser '
                  'igual a N ($numAdmins) — iter $i',
            );
          } finally {
            // 7. Cleanup — always runs even if assertions fail
            await SuperAdminDataFactory.cleanup(org);
          }
        },
      );
    }
  });
}
