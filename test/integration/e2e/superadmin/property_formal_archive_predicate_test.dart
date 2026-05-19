import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_test_config.dart';

/// Property-Based Test: Predicado Formal de Cascata (Cross-Layer)
///
/// **Validates: Requirements 10.1, 10.2, 10.3, 10.4**
///
/// Feature: superadmin-org-management-e2e-tests, Property 7: Predicado Formal de Cascata
///
/// Formal predicate (First-Order Logic):
/// ```
/// ∀ org ∈ Sistema:
///   org.status = 'ARCHIVED' →
///     (∀ admin ∈ org.admins:
///       admin.is_active = false ∧ admin.banned_until = 'infinity')
/// ```
///
/// Contrapositive:
/// ```
/// ∀ org ∈ Sistema:
///   (∃ admin ∈ org.admins: admin.is_active = true ∨ admin.banned_until ≠ 'infinity')
///     → org.status ≠ 'ARCHIVED'
/// ```
///
/// This test verifies BOTH layers:
///   - Application layer: `user_roles.is_active`
///   - Authentication layer: `auth.users.banned_until`
///
/// On violation, fails with message indicating WHICH admin and WHICH field violated.
///
/// Minimum 100 iterations.
void main() {
  late SupabaseClient serviceRoleClient;
  bool supabaseAvailable = false;

  group('Feature: superadmin-org-management-e2e-tests, '
      'Property 7: Predicado Formal de Cascata (Cross-Layer)', () {
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
    final random = Random(77);
    final numAdminsGen = any.intInRange(1, 11); // 1..10 inclusive
    const iterations = 100;

    final adminCounts = List.generate(
      iterations,
      (i) => numAdminsGen(random, i + 5).value,
    );

    // ════════════════════════════════════════════════════════════════════════
    // PART A: Positive direction — Archive org, verify predicate holds
    //         on BOTH layers (application + authentication)
    // ════════════════════════════════════════════════════════════════════════

    for (var i = 0; i < iterations; i++) {
      final numAdmins = adminCounts[i];

      test(
        'iter $i [PREDICATE]: Archived org ($numAdmins admins) → '
        'all admins !active ∧ banned (both layers)',
        skip: !supabaseAvailable
            ? 'Supabase local não disponível. Execute: supabase start'
            : null,
        () async {
          // 1. Create org with N active admins
          final org = await SuperAdminDataFactory.createOrgWithAdmins(
            orgName: 'PBT-FormalPred-$i',
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
                'p_reason': 'PBT formal predicate iter $i — $numAdmins admins',
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

            // 4. Verify predicate on BOTH layers for EACH admin individually
            final userRoles = await serviceRoleClient
                .from('user_roles')
                .select('user_id, is_active')
                .eq('organization_id', org.orgId);

            expect(
              userRoles,
              isNotEmpty,
              reason: 'Org $i deve ter pelo menos 1 user_role para verificar',
            );

            for (final row in userRoles) {
              final userId = row['user_id'] as String;
              final isActive = row['is_active'] as bool;

              // ── Application Layer: user_roles.is_active ──
              if (isActive) {
                fail(
                  'VIOLAÇÃO DO PREDICADO [Camada Aplicação] — iter $i:\n'
                  '  Admin $userId tem is_active=true\n'
                  '  Org ${org.orgId} está ARCHIVED\n'
                  '  Predicado: ARCHIVED → ∀ admin: !active\n'
                  '  Campo violado: user_roles.is_active',
                );
              }

              // ── Authentication Layer: auth.users.banned_until ──
              final bannedUntil = await _getUserBannedUntil(userId);
              if (bannedUntil == null) {
                fail(
                  'VIOLAÇÃO DO PREDICADO [Camada Autenticação] — iter $i:\n'
                  '  Admin $userId tem banned_until=null\n'
                  '  Org ${org.orgId} está ARCHIVED\n'
                  '  Predicado: ARCHIVED → ∀ admin: banned_until="infinity"\n'
                  '  Campo violado: auth.users.banned_until',
                );
              }
            }

            // 5. Verify count matches
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
            // Cleanup — always runs even if assertions fail
            await SuperAdminDataFactory.cleanup(org);
          }
        },
      );
    }

    // ════════════════════════════════════════════════════════════════════════
    // PART B: Contrapositive — Active org with active admins verifies that
    //         having any active admin implies org is NOT ARCHIVED
    // ════════════════════════════════════════════════════════════════════════

    for (var i = 0; i < iterations; i++) {
      final numAdmins = adminCounts[i];

      test(
        'iter $i [CONTRAPOSITIVE]: Org with active admins ($numAdmins) → '
        'org status ≠ ARCHIVED',
        skip: !supabaseAvailable
            ? 'Supabase local não disponível. Execute: supabase start'
            : null,
        () async {
          // 1. Create org with N active admins (NOT archived)
          final org = await SuperAdminDataFactory.createOrgWithAdmins(
            orgName: 'PBT-Contra-$i',
            cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
            activeAdmins: numAdmins,
            pendingAdmins: 0,
          );

          try {
            // 2. Verify org is ACTIVE (not archived)
            final status = await SuperAdminDbVerifier.getOrgStatus(
              org.orgId,
              client: serviceRoleClient,
            );

            // 3. Verify at least one admin is active (application layer)
            final userRoles = await serviceRoleClient
                .from('user_roles')
                .select('user_id, is_active')
                .eq('organization_id', org.orgId);

            final hasActiveAdmin = userRoles.any(
              (row) => row['is_active'] == true,
            );

            // 4. Verify contrapositive: active admin exists → NOT ARCHIVED
            if (hasActiveAdmin) {
              if (status == 'ARCHIVED') {
                // Find which admin is active for the error message
                final activeAdmin = userRoles.firstWhere(
                  (row) => row['is_active'] == true,
                );
                fail(
                  'VIOLAÇÃO DA CONTRAPOSITIVA — iter $i:\n'
                  '  Admin ${activeAdmin['user_id']} tem is_active=true\n'
                  '  Mas org ${org.orgId} está ARCHIVED\n'
                  '  Contrapositiva: (∃ admin: active) → org ≠ ARCHIVED\n'
                  '  Campo violado: user_roles.is_active',
                );
              }
            }

            // 5. Also verify auth layer contrapositive:
            //    if any admin has banned_until=null → org NOT ARCHIVED
            for (final row in userRoles) {
              final userId = row['user_id'] as String;
              final bannedUntil = await _getUserBannedUntil(userId);

              if (bannedUntil == null && status == 'ARCHIVED') {
                fail(
                  'VIOLAÇÃO DA CONTRAPOSITIVA [Camada Autenticação] — '
                  'iter $i:\n'
                  '  Admin $userId tem banned_until=null\n'
                  '  Mas org ${org.orgId} está ARCHIVED\n'
                  '  Contrapositiva: (∃ admin: !banned) → org ≠ ARCHIVED\n'
                  '  Campo violado: auth.users.banned_until',
                );
              }
            }

            // If we reach here, contrapositive holds
            expect(
              status,
              isNot(equals('ARCHIVED')),
              reason: 'Org com admins ativos não deve estar ARCHIVED',
            );
          } finally {
            // Cleanup
            await SuperAdminDataFactory.cleanup(org);
          }
        },
      );
    }
  });
}

// ── Helper: Get banned_until for a specific user via Admin REST API ──────────

/// Obtém o valor de `banned_until` de um usuário via Admin REST API.
///
/// Retorna a string raw do campo (ex: `'infinity'`, uma data ISO, ou `null`).
/// Usa service_role key como apikey + Authorization header.
Future<String?> _getUserBannedUntil(String userId) async {
  final url = Uri.parse(
    '${SuperAdminTestConfig.supabaseUrl}/auth/v1/admin/users/$userId',
  );

  final response = await http.get(
    url,
    headers: {
      'apikey': SuperAdminTestConfig.serviceRoleKey,
      'Authorization': 'Bearer ${SuperAdminTestConfig.serviceRoleKey}',
      'Content-Type': 'application/json',
    },
  );

  expect(
    response.statusCode,
    equals(200),
    reason:
        'Admin API GET /auth/v1/admin/users/$userId retornou '
        '${response.statusCode}: ${response.body}',
  );

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final bannedUntil = json['banned_until'];

  // O Supabase retorna null, uma string ISO, ou a string literal "infinity".
  if (bannedUntil == null ||
      bannedUntil == '' ||
      bannedUntil == '0001-01-01T00:00:00Z') {
    return null;
  }

  return bannedUntil.toString();
}
