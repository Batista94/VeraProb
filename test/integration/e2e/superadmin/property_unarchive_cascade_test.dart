import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_test_config.dart';

/// Property-Based Test: Integridade da Cascata de Desarquivamento
///
/// **Validates: Requirements 5.3, 9.2**
///
/// Feature: superadmin-org-management-e2e-tests, Property 2: Integridade da Cascata de Desarquivamento
///
/// For any archived organization with N blocked administrators (1 ≤ N ≤ 10),
/// when the unarchive operation is executed, ALL N administrators must have:
///   - `is_active = true` in `user_roles`
///   - `banned_until = null` in `auth.users`
///
/// The count of active users must equal exactly N.
///
/// Formal predicate:
/// ```
/// ∀ org ∈ Sistema:
///   org.status = 'ACTIVE' (após desarquivamento) →
///     (∀ admin ∈ org.admins:
///       admin.is_active = true ∧ admin.banned_until = null)
/// ```
///
/// This test runs WITHOUT UI — it exercises the unarchive cascade directly
/// via the `super_admin_unarchive_organization` RPC using service_role.
///
/// Steps per iteration:
/// 1. Create org with N active admins
/// 2. Archive it (via RPC) to block all admins
/// 3. Unarchive it (via RPC) to unblock all admins
/// 4. Verify org status is 'ACTIVE'
/// 5. Verify all admins have is_active=true
/// 6. Verify all admins have banned_until=null
/// 7. Verify count of active users == N
/// 8. Cleanup
///
/// Minimum 100 iterations.
void main() {
  late SupabaseClient serviceRoleClient;
  bool supabaseAvailable = false;

  group('Feature: superadmin-org-management-e2e-tests, '
      'Property 2: Integridade da Cascata de Desarquivamento', () {
    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;
      serviceRoleClient = SuperAdminTestConfig.createServiceRoleClient();
    });

    tearDownAll(() async {
      try {
        await Supabase.instance.dispose();
      } catch (_) {}
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
        'iter $i: Desarquivar org com $numAdmins admins desbloqueia todos',
        () async {
          // `skip:` is evaluated at collection time, before setUpAll sets
          // supabaseAvailable — guard at runtime instead.
          if (!supabaseAvailable) {
            markTestSkipped(
              'Supabase local não disponível. Execute: supabase start',
            );
            return;
          }
          // 1. Create org with N active admins
          final org = await SuperAdminDataFactory.createOrgWithAdmins(
            orgName: 'PBT-Unarchive-Cascade-$i',
            cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
            activeAdmins: numAdmins,
            pendingAdmins: 0,
          );

          try {
            // 2. Archive the org first (to set up blocked state)
            await serviceRoleClient.rpc<dynamic>(
              'super_admin_archive_organization',
              params: {
                'p_org_id': org.orgId,
                'p_reason':
                    'PBT setup arquivamento iter $i — $numAdmins admins',
                'p_super_admin_id': org.admins.first.userId,
              },
            );

            // Sanity check: org should be ARCHIVED after archive RPC
            final archivedStatus = await SuperAdminDbVerifier.getOrgStatus(
              org.orgId,
              client: serviceRoleClient,
            );
            expect(
              archivedStatus,
              equals('ARCHIVED'),
              reason:
                  'Org deve estar ARCHIVED antes do desarquivamento '
                  '(iter $i, N=$numAdmins)',
            );

            // 3. Unarchive the org (the operation under test)
            await serviceRoleClient.rpc<dynamic>(
              'super_admin_unarchive_organization',
              params: {
                'p_org_id': org.orgId,
                'p_reason':
                    'PBT cascata desarquivamento iter $i — $numAdmins admins',
                'p_super_admin_id': org.admins.first.userId,
              },
            );

            // 4. Verify org status is ACTIVE
            final status = await SuperAdminDbVerifier.getOrgStatus(
              org.orgId,
              client: serviceRoleClient,
            );
            expect(
              status,
              equals('ACTIVE'),
              reason:
                  'Org status deve ser ACTIVE após desarquivamento '
                  '(iter $i, N=$numAdmins)',
            );

            // 5. Verify ALL admins have is_active=true
            await SuperAdminDbVerifier.assertAllUsersActiveStatus(
              orgId: org.orgId,
              expectedActive: true,
              client: serviceRoleClient,
            );

            // 6. Verify ALL admins have banned_until=null
            await SuperAdminDbVerifier.assertAllUsersBannedStatus(
              orgId: org.orgId,
              shouldBeBanned: false,
              client: serviceRoleClient,
            );

            // 7. Verify count of active users == N
            final activeCount = await SuperAdminDbVerifier.countActiveUsers(
              org.orgId,
              client: serviceRoleClient,
            );
            expect(
              activeCount,
              equals(numAdmins),
              reason:
                  'Número de admins ativos ($activeCount) deve ser '
                  'igual a N ($numAdmins) — iter $i',
            );
          } finally {
            // 8. Cleanup — always runs even if assertions fail
            await SuperAdminDataFactory.cleanup(org);
          }
        },
      );
    }
  });
}
