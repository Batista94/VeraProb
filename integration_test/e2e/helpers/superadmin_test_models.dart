/// Modelos imutáveis de dados para a suíte de testes E2E do SuperAdmin.
///
/// Representam organizações e administradores criados pela [SuperAdminDataFactory]
/// e consumidos pelos testes de cenário (CT08–CT16) e property-based tests.
library;

/// Dados de uma organização criada para testes E2E.
///
/// Encapsula o estado completo de uma org de teste, incluindo seus admins,
/// permitindo verificações pós-operação e cleanup em `tearDownAll`.
///
/// Exemplo de uso:
/// ```dart
/// final org = await DataFactory.createOrgWithAdmins(
///   orgName: 'Viação Teste',
///   cnpj: '12345678000199',
///   activeAdmins: 2,
///   pendingAdmins: 1,
/// );
/// // ... executar operações ...
/// await DataFactory.cleanup(org);
/// ```
class TestOrgData {
  /// UUID da organização no banco de dados.
  final String orgId;

  /// Nome (razão social) da organização.
  final String orgName;

  /// CNPJ da organização (14 dígitos, sem formatação).
  final String cnpj;

  /// Status atual: `'ACTIVE'` ou `'ARCHIVED'`.
  final String status;

  /// Lista de administradores associados a esta organização.
  final List<TestAdminData> admins;

  const TestOrgData({
    required this.orgId,
    required this.orgName,
    required this.cnpj,
    required this.status,
    required this.admins,
  });

  /// Retorna uma cópia com os campos alterados.
  ///
  /// Útil para refletir mudanças de estado após operações (ex: arquivamento)
  /// sem mutar a instância original.
  TestOrgData copyWith({
    String? orgId,
    String? orgName,
    String? cnpj,
    String? status,
    List<TestAdminData>? admins,
  }) {
    return TestOrgData(
      orgId: orgId ?? this.orgId,
      orgName: orgName ?? this.orgName,
      cnpj: cnpj ?? this.cnpj,
      status: status ?? this.status,
      admins: admins ?? this.admins,
    );
  }

  @override
  String toString() =>
      'TestOrgData(orgId: $orgId, orgName: $orgName, cnpj: $cnpj, '
      'status: $status, admins: ${admins.length})';
}

/// Dados de um administrador criado para testes E2E.
///
/// Representa tanto admins ativos (que já aceitaram o convite) quanto
/// admins pendentes (convite enviado mas não aceito).
class TestAdminData {
  /// UUID do usuário no `auth.users` / `user_roles`.
  final String userId;

  /// Email do administrador.
  final String email;

  /// Role atribuída (ex: `'ORG_ADMIN'`, `'OPERATOR'`).
  final String role;

  /// Se o admin está ativo (`is_active` em `user_roles`).
  final bool isActive;

  /// Se o convite ainda está pendente de aceitação.
  final bool isPending;

  /// Token de convite (presente apenas para admins pendentes).
  final String? inviteToken;

  const TestAdminData({
    required this.userId,
    required this.email,
    required this.role,
    required this.isActive,
    required this.isPending,
    this.inviteToken,
  });

  @override
  String toString() =>
      'TestAdminData(userId: $userId, email: $email, role: $role, '
      'isActive: $isActive, isPending: $isPending)';
}
