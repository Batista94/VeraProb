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
  /// 3. Para cada admin pendente: cria user via Admin API, insere em
  ///    `user_roles` com `is_active=false`, gera token de convite em `invitations`
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
  /// Insere user via Admin API, cria `user_roles` com `is_active=false`,
  /// e gera um token de convite na tabela `invitations`.
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

      // 3. Deletar users via Admin API
      for (final admin in data.admins) {
        try {
          await client.auth.admin.deleteUser(admin.userId);
        } catch (e) {
          _log('cleanup: falha ao deletar user ${admin.userId}: $e');
        }
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

  /// Gera um CNPJ único de 14 dígitos para testes.
  ///
  /// Combina `DateTime.now().microsecondsSinceEpoch` com um componente
  /// aleatório para garantir unicidade entre execuções paralelas.
  static String generateUniqueCnpj() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomPart = _random.nextInt(99999).toString().padLeft(5, '0');
    final raw = '$timestamp$randomPart';
    // Pegar os últimos 14 dígitos para garantir formato correto
    return raw.substring(raw.length - 14);
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

    // 2. Inserir em user_roles
    await client.from('user_roles').insert({
      'user_id': userId,
      'organization_id': orgId,
      'role': 'TENANT_ADMIN',
      'is_active': isActive,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    // 3. Se pendente, criar invitation com token
    if (isPending) {
      inviteToken = _uuid.v4();
      await client.from('invitations').insert({
        'organization_id': orgId,
        'email': email,
        'role': 'TENANT_ADMIN',
        'token': inviteToken,
        'invited_by': userId, // auto-referência para simplificar seed
        'created_at_utc': DateTime.now().toUtc().toIso8601String(),
        'expires_at_utc': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String(),
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
}
