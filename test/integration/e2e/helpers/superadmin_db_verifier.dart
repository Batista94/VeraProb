import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'superadmin_test_config.dart';

/// Verificações diretas no banco de dados usando Service_Role_Client.
///
/// Cada método cria seu próprio client (ou aceita um opcional) para
/// bypassar RLS e validar o estado real do banco após operações de UI.
///
/// **Validates: Requirements 1.5, 9.1, 9.2, 9.3, 9.4, 9.5**
abstract class SuperAdminDbVerifier {
  // ── Active Status ─────────────────────────────────────────────────────────

  /// Verifica que TODOS os `user_roles` de uma org possuem
  /// `is_active` igual a [expectedActive].
  ///
  /// Lança [TestFailure] se algum registro divergir do esperado.
  ///
  /// **Validates: Requirements 9.1, 9.2**
  static Future<void> assertAllUsersActiveStatus({
    required String orgId,
    required bool expectedActive,
    SupabaseClient? client,
  }) async {
    final c = client ?? SuperAdminTestConfig.createServiceRoleClient();
    try {
      final rows = await c
          .from('user_roles')
          .select('user_id, is_active')
          .eq('organization_id', orgId);

      expect(
        rows,
        isNotEmpty,
        reason:
            'Org $orgId deve ter pelo menos 1 user_role para verificar status',
      );

      for (final row in rows) {
        final userId = row['user_id'] as String;
        final isActive = row['is_active'] as bool;
        expect(
          isActive,
          equals(expectedActive),
          reason:
              'user_roles.is_active para user $userId na org $orgId '
              'deveria ser $expectedActive, mas é $isActive',
        );
      }
    } finally {
      if (client == null) await c.dispose();
    }
  }

  // ── Banned Status ─────────────────────────────────────────────────────────

  /// Verifica `banned_until` para todos os usuários de uma org.
  ///
  /// Quando [shouldBeBanned] é `true`, espera `banned_until` não-nulo
  /// (tipicamente o sentinel `'9999-12-31 23:59:59+00'`).
  /// Quando `false`, espera `banned_until = null`.
  ///
  /// Reads directly from `auth.users` via `test_get_user_banned_until` RPC
  /// (SECURITY DEFINER) — bypasses GoTrue Admin REST API.
  ///
  /// **Validates: Requirements 9.1, 9.5**
  static Future<void> assertAllUsersBannedStatus({
    required String orgId,
    required bool shouldBeBanned,
    SupabaseClient? client,
  }) async {
    final c = client ?? SuperAdminTestConfig.createServiceRoleClient();
    try {
      // Obter todos os user_ids da org via user_roles.
      final rows = await c
          .from('user_roles')
          .select('user_id')
          .eq('organization_id', orgId);

      expect(
        rows,
        isNotEmpty,
        reason: 'Org $orgId deve ter pelo menos 1 user_role para verificar ban',
      );

      for (final row in rows) {
        final userId = row['user_id'] as String;

        // Chamar Admin API diretamente para obter banned_until.
        final bannedUntil = await _getUserBannedUntil(userId);

        if (shouldBeBanned) {
          expect(
            bannedUntil,
            isNotNull,
            reason:
                'auth.users.banned_until para user $userId na org $orgId '
                'deveria ser "infinity" (não-nulo), mas é null',
          );
        } else {
          expect(
            bannedUntil,
            isNull,
            reason:
                'auth.users.banned_until para user $userId na org $orgId '
                'deveria ser null (desbloqueado), mas é $bannedUntil',
          );
        }
      }
    } finally {
      if (client == null) await c.dispose();
    }
  }

  /// Returns `banned_until` for a user via SQL RPC — no GoTrue REST API.
  ///
  /// Uses `test_get_user_banned_until` (SECURITY DEFINER, service_role only).
  /// Avoids GoTrue Admin REST API which returns HTTP 500 when any auth.users
  /// row has banned_until='infinity' (migration 20260519000002_test_helpers_e2e).
  static Future<String?> _getUserBannedUntil(String userId) async {
    final client = SuperAdminTestConfig.createServiceRoleClient();
    try {
      final result = await client.rpc<String?>(
        'test_get_user_banned_until',
        params: {'p_user_id': userId},
      );
      if (result == null) return null;
      final str = result.toString();
      // Postgres epoch default / empty → treat as null (not banned)
      if (str.isEmpty || str == '0001-01-01 00:00:00.000Z') return null;
      return str;
    } finally {
      await client.dispose();
    }
  }

  // ── Audit Log ─────────────────────────────────────────────────────────────

  /// Verifica existência de registro em `system_audit_log` para a org e tipo.
  ///
  /// Retorna o registro encontrado (mais recente) para inspeção adicional.
  /// Lança [TestFailure] se nenhum registro for encontrado ou se
  /// [reasonNotNull] for `true` e o campo `reason` estiver nulo.
  ///
  /// **Validates: Requirements 9.3**
  static Future<Map<String, dynamic>> assertAuditLogExists({
    required String orgId,
    required String eventType,
    bool reasonNotNull = true,
    SupabaseClient? client,
  }) async {
    final c = client ?? SuperAdminTestConfig.createServiceRoleClient();
    try {
      final rows = await c
          .from('system_audit_log')
          .select()
          .eq('organization_id', orgId)
          .eq('event_type', eventType)
          .order('occurred_at', ascending: false)
          .limit(1);

      expect(
        rows,
        isNotEmpty,
        reason:
            'system_audit_log deve conter registro com event_type=$eventType '
            'para org $orgId',
      );

      final record = rows.first;

      if (reasonNotNull) {
        expect(
          record['reason'],
          isNotNull,
          reason:
              'system_audit_log.reason não deve ser nulo para '
              'event_type=$eventType na org $orgId',
        );
        expect(
          (record['reason'] as String).trim(),
          isNotEmpty,
          reason:
              'system_audit_log.reason não deve ser vazio para '
              'event_type=$eventType na org $orgId',
        );
      }

      return record;
    } finally {
      if (client == null) await c.dispose();
    }
  }

  // ── Identity Immutability (INV-1) ─────────────────────────────────────────

  /// Verifica que `cnpj` da organização não mudou após operações.
  ///
  /// Compara o valor atual no banco com [expectedCnpj].
  /// Lança [TestFailure] se houver divergência.
  ///
  /// **Validates: Requirements 9.4 (INV-1)**
  static Future<void> assertIdentityImmutable({
    required String orgId,
    required String expectedCnpj,
    SupabaseClient? client,
  }) async {
    final c = client ?? SuperAdminTestConfig.createServiceRoleClient();
    try {
      final rows = await c
          .from('organizations')
          .select('id, cnpj')
          .eq('id', orgId)
          .limit(1);

      expect(
        rows,
        isNotEmpty,
        reason: 'Organização $orgId deve existir no banco',
      );

      final record = rows.first;

      // Verificar que o ID não mudou (sanity check).
      expect(
        record['id'],
        equals(orgId),
        reason: 'organization.id deve permanecer inalterado',
      );

      // Verificar que o CNPJ não mudou.
      expect(
        record['cnpj'],
        equals(expectedCnpj),
        reason:
            'organization.cnpj deve permanecer inalterado. '
            'Esperado: $expectedCnpj, Atual: ${record['cnpj']}',
      );
    } finally {
      if (client == null) await c.dispose();
    }
  }

  // ── Count Helpers ─────────────────────────────────────────────────────────

  /// Conta usuários ativos (`is_active=true`) de uma organização.
  ///
  /// **Validates: Requirements 9.5**
  static Future<int> countActiveUsers(
    String orgId, {
    SupabaseClient? client,
  }) async {
    final c = client ?? SuperAdminTestConfig.createServiceRoleClient();
    try {
      final rows = await c
          .from('user_roles')
          .select('user_id')
          .eq('organization_id', orgId)
          .eq('is_active', true);

      return rows.length;
    } finally {
      if (client == null) await c.dispose();
    }
  }

  /// Conta usuários bloqueados (`is_active=false`) de uma organização.
  ///
  /// Útil para property tests que verificam a cascata de bloqueio.
  ///
  /// **Validates: Requirements 9.1, 9.5**
  static Future<int> countBlockedUsers(
    String orgId, {
    SupabaseClient? client,
  }) async {
    final c = client ?? SuperAdminTestConfig.createServiceRoleClient();
    try {
      final rows = await c
          .from('user_roles')
          .select('user_id')
          .eq('organization_id', orgId)
          .eq('is_active', false);

      return rows.length;
    } finally {
      if (client == null) await c.dispose();
    }
  }

  // ── Org Status ────────────────────────────────────────────────────────────

  /// Retorna o status atual da organização (`'ACTIVE'`, `'ARCHIVED'`, etc.).
  ///
  /// Lança [TestFailure] se a organização não for encontrada.
  static Future<String> getOrgStatus(
    String orgId, {
    SupabaseClient? client,
  }) async {
    final c = client ?? SuperAdminTestConfig.createServiceRoleClient();
    try {
      final rows = await c
          .from('organizations')
          .select('status')
          .eq('id', orgId)
          .limit(1);

      expect(
        rows,
        isNotEmpty,
        reason: 'Organização $orgId deve existir no banco',
      );

      return rows.first['status'] as String;
    } finally {
      if (client == null) await c.dispose();
    }
  }
}
