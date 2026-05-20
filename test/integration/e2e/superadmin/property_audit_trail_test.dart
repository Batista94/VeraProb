import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_test_config.dart';

/// Property-Based Test: Completude do Audit Trail
///
/// **Validates: Requirements 4.5, 9.3**
///
/// Feature: superadmin-org-management-e2e-tests, Property 4: Completude do Audit Trail
///
/// For any critical operation executed (archive, unarchive), there must exist
/// a corresponding record in `system_audit_log` with:
///   - `reason` non-null and non-empty
///   - `organization_id` matching the target org
///   - `event_type` matching the operation performed
///
/// Formal predicate:
/// ```
/// ∀ op ∈ {ARCHIVE, UNARCHIVE}:
///   executed(op, org) →
///     (∃ log ∈ system_audit_log:
///       log.organization_id = org.id ∧
///       log.event_type = op ∧
///       log.reason ≠ null ∧
///       log.reason.trim() ≠ '')
/// ```
///
/// This test runs WITHOUT UI — it exercises operations directly
/// via RPC using service_role.
///
/// Minimum 100 iterations.
void main() {
  late SupabaseClient serviceRoleClient;
  bool supabaseAvailable = false;

  group('Feature: superadmin-org-management-e2e-tests, '
      'Property 4: Completude do Audit Trail', () {
    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;
      serviceRoleClient = SuperAdminTestConfig.createServiceRoleClient();
    });

    tearDownAll(() async {
      if (!supabaseAvailable) return;
      await serviceRoleClient.dispose();
    });

    // ── Operation types ───────────────────────────────────────────────────
    // 0 = archive only
    // 1 = archive + unarchive (to test unarchive audit trail)
    const iterations = 100;
    final random = Random(77);
    final operationTypeGen = any.intInRange(0, 2); // 0 or 1
    final numAdminsGen = any.intInRange(1, 4); // 1..3 inclusive

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
      final opLabel = opType == 0 ? 'archive' : 'archive+unarchive';

      test(
        'iter $i: $opLabel com $numAdmins admins gera audit log completo',
        skip: !supabaseAvailable
            ? 'Supabase local não disponível. Execute: supabase start'
            : null,
        () async {
          // 1. Create org with N active admins
          final org = await SuperAdminDataFactory.createOrgWithAdmins(
            orgName: 'PBT-AuditTrail-$i',
            cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
            activeAdmins: numAdmins,
            pendingAdmins: 0,
          );

          try {
            // 2. Execute archive operation
            final archiveReason =
                'PBT audit trail iter $i — archive ($numAdmins admins)';
            await serviceRoleClient.rpc<dynamic>(
              'super_admin_archive_organization',
              params: {
                'p_org_id': org.orgId,
                'p_reason': archiveReason,
                'p_super_admin_id': org.admins.first.userId,
              },
            );

            // 3. Verify audit log exists for ARCHIVE operation
            final archiveLog = await SuperAdminDbVerifier.assertAuditLogExists(
              orgId: org.orgId,
              eventType: 'ORG_ARCHIVED',
              reasonNotNull: true,
              client: serviceRoleClient,
            );

            // 4. Verify organization_id is correct in audit record
            expect(
              archiveLog['organization_id'],
              equals(org.orgId),
              reason:
                  'audit log organization_id deve ser ${org.orgId} '
                  '(iter $i, op=archive)',
            );

            // 5. If opType == 1, also unarchive and verify its audit log
            if (opType == 1) {
              final unarchiveReason =
                  'PBT audit trail iter $i — unarchive ($numAdmins admins)';
              await serviceRoleClient.rpc<dynamic>(
                'super_admin_unarchive_organization',
                params: {
                  'p_org_id': org.orgId,
                  'p_reason': unarchiveReason,
                  'p_super_admin_id': org.admins.first.userId,
                },
              );

              // 6. Verify audit log exists for UNARCHIVE operation
              final unarchiveLog =
                  await SuperAdminDbVerifier.assertAuditLogExists(
                    orgId: org.orgId,
                    eventType: 'ORG_UNARCHIVED',
                    reasonNotNull: true,
                    client: serviceRoleClient,
                  );

              // 7. Verify organization_id is correct in unarchive audit record
              expect(
                unarchiveLog['organization_id'],
                equals(org.orgId),
                reason:
                    'audit log organization_id deve ser ${org.orgId} '
                    '(iter $i, op=unarchive)',
              );
            }
          } finally {
            // 8. Cleanup — always runs even if assertions fail
            await SuperAdminDataFactory.cleanup(org);
          }
        },
      );
    }
  });
}
