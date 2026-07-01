import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_test_config.dart';

/// Property-Based Test: Imutabilidade de Identidade Core
///
/// **Validates: Requirements 9.4**
///
/// Feature: superadmin-org-management-e2e-tests, Property 5: Imutabilidade de Identidade Core
///
/// For any operation executed on an organization (archive, archive+unarchive,
/// archive+unarchive+archive), the fields `organization_id` and `cnpj` must
/// remain unchanged in the database.
///
/// Formal predicate:
/// ```
/// ∀ org ∈ Sistema, ∀ op ∈ {archive, unarchive, cycle}:
///   let (id_before, cnpj_before) = identity(org) in
///   execute(op, org) →
///     identity(org) = (id_before, cnpj_before)
/// ```
///
/// Operation types:
///   0 = archive only
///   1 = archive + unarchive (full cycle)
///   2 = archive + unarchive + archive (double cycle)
///
/// This test runs WITHOUT UI — it exercises operations directly
/// via RPC using service_role.
///
/// Minimum 100 iterations.
void main() {
  late SupabaseClient serviceRoleClient;
  bool supabaseAvailable = false;

  group('Feature: superadmin-org-management-e2e-tests, '
      'Property 5: Imutabilidade de Identidade Core', () {
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
    const iterations = 100;
    final random = Random(99);
    final operationTypeGen = any.intInRange(0, 3); // 0, 1, or 2
    final numAdminsGen = any.intInRange(1, 6); // 1..5 inclusive

    final operationTypes = List.generate(
      iterations,
      (i) => operationTypeGen(random, i + 3).value,
    );

    final adminCounts = List.generate(
      iterations,
      (i) => numAdminsGen(random, i + 7).value,
    );

    for (var i = 0; i < iterations; i++) {
      final opType = operationTypes[i];
      final numAdmins = adminCounts[i];
      final opLabel = switch (opType) {
        0 => 'archive',
        1 => 'archive+unarchive',
        _ => 'archive+unarchive+archive',
      };

      test(
        'iter $i: $opLabel com $numAdmins admins preserva identity (id+cnpj)',
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
            orgName: 'PBT-Identity-$i',
            cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
            activeAdmins: numAdmins,
            pendingAdmins: 0,
          );

          // Record original identity
          final originalOrgId = org.orgId;
          final originalCnpj = org.cnpj;

          try {
            // 2. Execute operation(s) based on opType
            // --- Archive ---
            await serviceRoleClient.rpc<dynamic>(
              'super_admin_archive_organization',
              params: {
                'p_org_id': org.orgId,
                'p_reason': 'PBT identity iter $i — archive',
                'p_super_admin_id': org.admins.first.userId,
              },
            );

            // Verify identity after archive
            await SuperAdminDbVerifier.assertIdentityImmutable(
              orgId: originalOrgId,
              expectedCnpj: originalCnpj,
              client: serviceRoleClient,
            );

            // --- Unarchive (if opType >= 1) ---
            if (opType >= 1) {
              await serviceRoleClient.rpc<dynamic>(
                'super_admin_unarchive_organization',
                params: {
                  'p_org_id': org.orgId,
                  'p_reason': 'PBT identity iter $i — unarchive',
                  'p_super_admin_id': org.admins.first.userId,
                },
              );

              // Verify identity after unarchive
              await SuperAdminDbVerifier.assertIdentityImmutable(
                orgId: originalOrgId,
                expectedCnpj: originalCnpj,
                client: serviceRoleClient,
              );
            }

            // --- Archive again (if opType == 2) ---
            if (opType == 2) {
              await serviceRoleClient.rpc<dynamic>(
                'super_admin_archive_organization',
                params: {
                  'p_org_id': org.orgId,
                  'p_reason': 'PBT identity iter $i — re-archive',
                  'p_super_admin_id': org.admins.first.userId,
                },
              );

              // Verify identity after re-archive
              await SuperAdminDbVerifier.assertIdentityImmutable(
                orgId: originalOrgId,
                expectedCnpj: originalCnpj,
                client: serviceRoleClient,
              );
            }
          } finally {
            // 3. Cleanup — always runs even if assertions fail
            await SuperAdminDataFactory.cleanup(org);
          }
        },
      );
    }
  });
}
