import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'superadmin_test_config.dart';
import 'superadmin_test_models.dart';

/// Factory para criação e limpeza de massa de dados isolada para testes E2E.
///
/// Usa `service_role` key para inserção direta no banco, bypassando RLS e
/// validações de UI. Cada método cria seu próprio [SupabaseClient] e faz
/// `dispose()` ao final para evitar vazamento de recursos.
///
/// **Padrão de uso:**
/// ```dart
/// late TestOrgData testOrg;
///
/// setUpAll(() async {
///   testOrg = await SuperAdminDataFactory.createOrgWithAdmins(
///     orgName: 'Viação Teste',
///     cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
///     activeAdmins: 2,
///     pendingAdmins: 1,
///   );
/// });
///
/// tearDownAll(() async {
///   await SuperAdminDataFactory.cleanup(testOrg);
/// });
/// ```
///
/// **Validates: Requirements 1.4, 1.6, 9.6**
abstract class SuperAdminDataFactory {
  static const _uuid = Uuid();
  static final _random = Random();

  // ── Criação de Organização com Admins ─────────────────────────────────────

  /// Cria uma organização com N admins ativos e M admins pendentes.
  ///
  /// Fluxo:
  /// 1. Insere na tabela `organizations` com status `'ACTIVE'`
  /// 2. Para cada admin ativo: cria user via Admin API, insere em `user_roles`
  ///    com `is_active=true`
  /// 3. Para cada admin pendente: cria user via Admin API, gera token de
  ///    convite em `invitations` — sem inserção em `user_roles` (a row só
  ///    existe após aceite do convite; inserção precoce suprime o convite no
  ///    filtro NOT EXISTS de `super_admin_get_org_members`)
  ///
  /// Retorna [TestOrgData] com todos os dados criados para uso nos testes
  /// e posterior cleanup.
  static Future<TestOrgData> createOrgWithAdmins({
    required String orgName,
    required String cnpj,
    int activeAdmins = 2,
    int pendingAdmins = 1,
  }) async {
    final client = SuperAdminTestConfig.createServiceRoleClient();
    try {
      // Idempotência: purga remanescentes de runs anteriores que tenham
      // o mesmo nome (cnpj varia a cada run). Determinismo > tolerância
      // (INV-15). Caso contrário, status='ARCHIVED' órfão envenena a UI.
      await _purgeOrgsByName(client, orgName);

      // 1. Criar organização
      final orgId = _uuid.v4();
      await client.from('organizations').insert({
        'id': orgId,
        'name': orgName,
        'cnpj': cnpj,
        'status': 'ACTIVE',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final admins = <TestAdminData>[];

      // 2. Criar admins ativos
      for (var i = 0; i < activeAdmins; i++) {
        final email = _generateTestEmail(orgId, 'active', i);
        final admin = await _createAdminInternal(
          client: client,
          orgId: orgId,
          email: email,
          isActive: true,
          isPending: false,
        );
        admins.add(admin);
      }

      // 3. Criar admins pendentes
      for (var i = 0; i < pendingAdmins; i++) {
        final email = _generateTestEmail(orgId, 'pending', i);
        final admin = await _createAdminInternal(
          client: client,
          orgId: orgId,
          email: email,
          isActive: false,
          isPending: true,
        );
        admins.add(admin);
      }

      return TestOrgData(
        orgId: orgId,
        orgName: orgName,
        cnpj: cnpj,
        status: 'ACTIVE',
        admins: admins,
      );
    } finally {
      await client.dispose();
    }
  }

  // ── Criação Individual de Admins ──────────────────────────────────────────

  /// Cria um admin pendente (convite não aceito) para uma org existente.
  ///
  /// Insere user via Admin API e gera token de convite em `invitations`.
  /// Não insere em `user_roles` — a row só existe após aceite (produção).
  static Future<TestAdminData> createPendingAdmin({
    required String orgId,
    required String email,
  }) async {
    final client = SuperAdminTestConfig.createServiceRoleClient();
    try {
      return await _createAdminInternal(
        client: client,
        orgId: orgId,
        email: email,
        isActive: false,
        isPending: true,
      );
    } finally {
      await client.dispose();
    }
  }

  /// Cria um admin ativo para uma org existente.
  ///
  /// Insere user via Admin API e cria `user_roles` com `is_active=true`.
  static Future<TestAdminData> createActiveAdmin({
    required String orgId,
    required String email,
  }) async {
    final client = SuperAdminTestConfig.createServiceRoleClient();
    try {
      return await _createAdminInternal(
        client: client,
        orgId: orgId,
        email: email,
        isActive: true,
        isPending: false,
      );
    } finally {
      await client.dispose();
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Limpa todos os dados de teste criados, em ordem reversa de FK.
  ///
  /// Ordem de deleção:
  /// 1. `invitations` (referencia `organizations` e `auth.users`)
  /// 2. `user_roles` (referencia `organizations` e `auth.users`)
  /// 3. `auth.users` via Admin API (`deleteUser`)
  /// 4. `organizations`
  ///
  /// Erros são logados mas não propagados — cleanup não deve falhar testes.
  static Future<void> cleanup(TestOrgData data) async {
    final client = SuperAdminTestConfig.createServiceRoleClient();
    try {
      // 1. Deletar invitations da org
      try {
        await client
            .from('invitations')
            .delete()
            .eq('organization_id', data.orgId);
      } catch (e) {
        // Log mas não falha — pode não existir invitations
        _log(
          'cleanup: falha ao deletar invitations para org ${data.orgId}: $e',
        );
      }

      // 2. Deletar user_roles da org
      try {
        await client
            .from('user_roles')
            .delete()
            .eq('organization_id', data.orgId);
      } catch (e) {
        _log('cleanup: falha ao deletar user_roles para org ${data.orgId}: $e');
      }

      // 3. Deletar users via Admin API (sequencial com retry — GoTrue
      // serializa writes em auth.users; requests concorrentes geram locks e
      // 500s intermitentes no teardown).
      for (final admin in data.admins) {
        await _deleteUserWithRetry(client, admin.userId, context: 'cleanup');
      }

      // 4. Deletar organização
      try {
        await client.from('organizations').delete().eq('id', data.orgId);
      } catch (e) {
        _log('cleanup: falha ao deletar org ${data.orgId}: $e');
      }
    } finally {
      await client.dispose();
    }
  }

  // ── Geradores de Dados ────────────────────────────────────────────────────

  /// Gera um CNPJ único e estruturalmente válido (modulo-11) para testes.
  ///
  /// Gera 12 dígitos da base + 2 check digits via algoritmo brasileiro.
  /// CNPJs válidos são exigidos pelo wizard (`CnpjValidator.isValid`); sem
  /// check digits corretos, o wizard rejeita por "CNPJ inválido" antes de
  /// chegar à verificação de duplicidade (Req 9.6).
  static String generateUniqueCnpj() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(99999).toString().padLeft(5, '0');
    final raw = '$timestamp$randomPart';
    // Tomar 12 dígitos base (positions 0–11).
    final base = raw.substring(raw.length - 12);
    final baseDigits = base.split('').map(int.parse).toList();

    int checkDigit(List<int> digits, List<int> weights) {
      final sum = List.generate(
        digits.length,
        (i) => digits[i] * weights[i],
      ).fold<int>(0, (a, b) => a + b);
      final rem = sum % 11;
      return rem < 2 ? 0 : 11 - rem;
    }

    const w1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const w2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    final d1 = checkDigit(baseDigits, w1);
    final d2 = checkDigit([...baseDigits, d1], w2);
    return '$base$d1$d2';
  }

  /// Gera um nome longo com caracteres brasileiros para testes de overflow.
  ///
  /// O nome gerado inclui caracteres especiais (ç, ã, õ, é, ü) para
  /// validar renderização correta de texto com diacríticos.
  ///
  /// Exemplo com `length=100`:
  /// `'Viação São José dos Campos Transportes Ltda — Razão Social Completa...'`
  static String generateLongName(int length) {
    const pattern =
        'Viação São José dos Campos Transportes & Logística Ltda — Razão Social Completa com Caracteres Especiais: ç, ã, õ, é, ü ';
    final buffer = StringBuffer();
    while (buffer.length < length) {
      buffer.write(pattern);
    }
    return buffer.toString().substring(0, length);
  }

  /// Verifica se um CNPJ já existe na tabela `organizations`.
  ///
  /// Usado antes de testes de duplicidade para confirmar que o CNPJ
  /// de referência está presente no banco.
  ///
  /// **Validates: Requirement 9.6**
  static Future<bool> cnpjExistsInDb(String cnpj) async {
    final client = SuperAdminTestConfig.createServiceRoleClient();
    try {
      final rows = await client
          .from('organizations')
          .select('id')
          .eq('cnpj', cnpj)
          .limit(1);
      return rows.isNotEmpty;
    } finally {
      await client.dispose();
    }
  }

  // ── Métodos Internos ──────────────────────────────────────────────────────

  /// Cria um admin (ativo ou pendente) com todas as inserções necessárias.
  static Future<TestAdminData> _createAdminInternal({
    required SupabaseClient client,
    required String orgId,
    required String email,
    required bool isActive,
    required bool isPending,
  }) async {
    // isPending and isActive are mutually exclusive — pending invite has no role yet.
    assert(
      !isPending || !isActive,
      'isPending and isActive are mutually exclusive',
    );

    // 1. Criar user via Supabase Admin API
    final userResponse = await client.auth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: 'TestPassword123!',
        emailConfirm: true,
        appMetadata: {'org_id': orgId, 'role': 'TENANT_ADMIN'},
      ),
    );

    final userId = userResponse.user!.id;
    String? inviteToken;

    if (isPending) {
      // 2. Pendente: apenas invitation — SEM user_roles.
      // super_admin_get_org_members usa NOT EXISTS (user_roles JOIN auth.users)
      // para surfar convites pendentes. Uma row em user_roles aqui suprime o
      // convite nesse filtro e exibe o usuário como inativo em vez de pendente.
      inviteToken = _uuid.v4();
      await client.from('invitations').insert({
        'organization_id': orgId,
        'email': email,
        'role': 'TENANT_ADMIN',
        'token': inviteToken,
        'invited_by':
            userId, // test convention: self-reference (no real inviter in seed)
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'expires_at_utc': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String(),
      });
    } else {
      // 2. Ativo (ou inativo já aceito): inserir user_roles.
      await client.from('user_roles').insert({
        'user_id': userId,
        'organization_id': orgId,
        'role': 'TENANT_ADMIN',
        'is_active': isActive,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    return TestAdminData(
      userId: userId,
      email: email,
      role: 'TENANT_ADMIN',
      isActive: isActive,
      isPending: isPending,
      inviteToken: inviteToken,
    );
  }

  /// Gera um email de teste único baseado no orgId e índice.
  static String _generateTestEmail(String orgId, String type, int index) {
    final shortId = orgId.substring(0, 8);
    return 'test-$type-$index-$shortId@e2e.veraprob.dev';
  }

  /// Log interno para debugging de cleanup (não falha testes).
  static void _log(String message) {
    // ignore: avoid_print
    print('[SuperAdminDataFactory] $message');
  }

  /// Deleta um usuário via Admin API com retry e backoff exponencial.
  ///
  /// GoTrue serializa writes em `auth.users`; calls rápidos e consecutivos
  /// causam lock contention e retornam HTTP 500 transitório. Retry resolve
  /// sem alterar a semântica do cleanup (best-effort, falhas são logadas).
  static Future<void> _deleteUserWithRetry(
    SupabaseClient client,
    String userId, {
    required String context,
  }) async {
    const maxAttempts = 5;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await client.auth.admin.deleteUser(userId);
        // Pausa pós-sucesso: dá ao GoTrue tempo de liberar o write lock
        // antes da próxima deleção — evita lock contention em lote.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return;
      } catch (e) {
        if (attempt < maxAttempts - 1) {
          // Backoff exponencial: 500 ms, 1 000 ms, 2 000 ms, 4 000 ms.
          final delayMs = 500 * (1 << attempt);
          _log(
            '$context: deleteUser $userId tentativa ${attempt + 1} falhou '
            '($e). Retry em ${delayMs}ms...',
          );
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        } else {
          _log(
            '$context: deleteUser $userId falhou após $maxAttempts '
            'tentativas: $e',
          );
        }
      }
    }
  }

  /// Remove orgs remanescentes (qualquer status) com o nome dado.
  ///
  /// Reutilizado por [createOrgWithAdmins] para garantir idempotência
  /// quando uma run anterior abortou e deixou rows com status='ARCHIVED'.
  /// Mesma ordem de FK do [cleanup]: invitations → user_roles → auth.users
  /// → organizations. Todas falhas são logadas e ignoradas — purge é
  /// best-effort.
  static Future<void> _purgeOrgsByName(
    SupabaseClient client,
    String orgName,
  ) async {
    try {
      final rows = await client
          .from('organizations')
          .select('id')
          .eq('name', orgName);
      if (rows.isEmpty) return;

      final orgIds = rows.map((r) => r['id'] as String).toList(growable: false);

      for (final orgId in orgIds) {
        // 1a. Coletar user_ids da org antes de deletar user_roles
        List<String> userIds = const [];
        try {
          final roleRows = await client
              .from('user_roles')
              .select('user_id')
              .eq('organization_id', orgId);
          userIds = roleRows
              .map((r) => r['user_id'] as String)
              .toList(growable: false);
        } catch (e) {
          _log('purge: falha ao listar user_roles de $orgId: $e');
        }

        // 1b. Coletar user_ids de admins pendentes via invitations.invited_by
        // ANTES de deletar invitations. Test convention: invited_by é setado
        // como o próprio userId do pendente (self-reference no seed). Verificado
        // via email domain guard para evitar deleção acidental de não-test users.
        final pendingUserIds = <String>[];
        try {
          final inviteRows = await client
              .from('invitations')
              .select('invited_by')
              .eq('organization_id', orgId);
          for (final row in inviteRows) {
            final invitedBy = row['invited_by'] as String?;
            if (invitedBy == null || userIds.contains(invitedBy)) continue;
            try {
              final resp = await client.auth.admin.getUserById(invitedBy);
              if (resp.user?.email?.endsWith('@e2e.veraprob.dev') == true) {
                pendingUserIds.add(invitedBy);
              }
            } catch (_) {
              // user pode não existir — skip
            }
          }
        } catch (e) {
          _log('purge: falha ao coletar pending admin IDs de $orgId: $e');
        }

        // 2. invitations
        try {
          await client
              .from('invitations')
              .delete()
              .eq('organization_id', orgId);
        } catch (e) {
          _log('purge: falha ao deletar invitations de $orgId: $e');
        }

        // 3. user_roles
        try {
          await client.from('user_roles').delete().eq('organization_id', orgId);
        } catch (e) {
          _log('purge: falha ao deletar user_roles de $orgId: $e');
        }

        // 4. auth.users — ativos/inativos (user_roles) + pendentes (invitations)
        for (final userId in [...userIds, ...pendingUserIds]) {
          await _deleteUserWithRetry(client, userId, context: 'purge');
        }

        // 5. organização
        try {
          await client.from('organizations').delete().eq('id', orgId);
        } catch (e) {
          _log('purge: falha ao deletar org $orgId: $e');
        }
      }
    } catch (e) {
      _log('purge: falha ao buscar orgs por nome "$orgName": $e');
    }
  }
}
