import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_test_config.dart';

/// Property-Based Test: Idempotência de Double-Click
///
/// **Validates: Requirements 8.3**
///
/// Feature: superadmin-org-management-e2e-tests, Property 6: Idempotência de Double-Click
///
/// For any organization with N active administrators (1 ≤ N ≤ 3), when the
/// archive RPC is called K times concurrently (2 ≤ K ≤ 5), the system must:
///   - Archive the organization exactly once (status = 'ARCHIVED')
///   - Create exactly 1 audit log entry for ARCHIVE_ORGANIZATION
///
/// The RPC must handle concurrent calls gracefully — either by idempotent
/// execution or by rejecting duplicate calls.
///
/// Formal predicate:
/// ```
/// ∀ org ∈ Sistema, ∀ K ∈ {2..5}:
///   concurrent_calls(archive, org, K) →
///     (org.status = 'ARCHIVED' ∧
///      count(audit_log WHERE org_id = org.id AND event_type = 'ARCHIVE_ORGANIZATION') = 1)
/// ```
///
/// This test runs WITHOUT UI — it exercises the archive RPC directly
/// via service_role with concurrent Future.wait calls.
///
/// Minimum 100 iterations.
void main() {
  late SupabaseClient serviceRoleClient;
  bool supabaseAvailable = false;

  group('Feature: superadmin-org-management-e2e-tests, '
      'Property 6: Idempotência de Double-Click', () {
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
    final random = Random(99);
    final numClicksGen = any.intInRange(2, 6); // 2..5 inclusive
    final numAdminsGen = any.intInRange(1, 4); // 1..3 inclusive
    const iterations = 100;

    final clickCounts = List.generate(
      iterations,
      (i) => numClicksGen(random, i + 3).value,
    );

    final adminCounts = List.generate(
      iterations,
      (i) => numAdminsGen(random, i + 7).value,
    );

    for (var i = 0; i < iterations; i++) {
      final numClicks = clickCounts[i];
      final numAdmins = adminCounts[i];

      test(
        'iter $i: $numClicks concurrent archive calls com $numAdmins admins '
        'resulta em exatamente 1 operação',
        skip: !supabaseAvailable
            ? 'Supabase local não disponível. Execute: supabase start'
            : null,
        () async {
          // 1. Create org with N active admins
          final org = await SuperAdminDataFactory.createOrgWithAdmins(
            orgName: 'PBT-DoubleClick-$i',
            cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
            activeAdmins: numAdmins,
            pendingAdmins: 0,
          );

          try {
            // 2. Fire N concurrent archive RPC calls (simulating double-click)
            final futures = List.generate(numClicks, (clickIdx) async {
              try {
                await serviceRoleClient.rpc(
                  'super_admin_archive_organization',
                  params: {
                    'p_org_id': org.orgId,
                    'p_reason': 'PBT double-click iter $i — click $clickIdx',
                    'p_super_admin_id': org.admins.first.userId,
                  },
                );
              } catch (_) {
                // Expected: some concurrent calls may fail with conflict
                // errors. This is acceptable — idempotency means only 1
                // succeeds or all produce the same final state.
              }
            });

            await Future.wait(futures);

            // 3. Verify org status is ARCHIVED (exactly once)
            final status = await SuperAdminDbVerifier.getOrgStatus(
              org.orgId,
              client: serviceRoleClient,
            );
            expect(
              status,
              equals('ARCHIVED'),
              reason:
                  'Org status deve ser ARCHIVED após $numClicks concurrent '
                  'calls (iter $i, N=$numAdmins)',
            );

            // 4. Verify exactly 1 audit log entry for ARCHIVE_ORGANIZATION
            final auditLogs = await serviceRoleClient
                .from('system_audit_log')
                .select()
                .eq('organization_id', org.orgId)
                .eq('event_type', 'ARCHIVE_ORGANIZATION');

            expect(
              auditLogs.length,
              equals(1),
              reason:
                  'Deve existir exatamente 1 registro de audit log para '
                  'ARCHIVE_ORGANIZATION na org ${org.orgId} após '
                  '$numClicks concurrent calls (iter $i). '
                  'Encontrados: ${auditLogs.length}',
            );
          } finally {
            // 5. Cleanup — always runs even if assertions fail
            await SuperAdminDataFactory.cleanup(org);
          }
        },
      );
    }
  });
}
