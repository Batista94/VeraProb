/// Categoria de evento de auditoria para classificação visual na
/// camada de apresentação.
///
/// Cada evento de auditoria (`SystemAuditLogView.eventType`) é mapeado
/// deterministicamente para uma das quatro categorias, sem lógica fuzzy.
///
/// **Mapeamento por substring (uppercase):**
/// - `POOL_LIMIT`, `STORAGE_QUOTA`, `SCHEMA`, `REPLICATION` → [infrastructure]
/// - `PLAN_CHANGED`, `QUOTA`, `ORG_CREATED`, `ORG_ARCHIVED`, `ORG_UNARCHIVED` → [governance]
/// - `SECRET`, `IMPERSONATION`, `MFA`, `AUTH` → [security]
/// - Demais → [operational]
///
/// **INV-4:** Enum puro Dart — sem dependências de domínio.
enum AuditEventCategory {
  /// Eventos de infraestrutura técnica (pool, storage, schema, replicação).
  infrastructure,

  /// Eventos de governança organizacional (plano, cotas, ciclo de vida de org).
  governance,

  /// Eventos de segurança (segredos, impersonação, MFA, autenticação).
  security,

  /// Eventos operacionais genéricos (fallback para tipos não mapeados).
  operational;

  /// Mapeamento determinístico de `eventType` para categoria (Req 7.4).
  ///
  /// Converte [eventType] para uppercase e verifica substrings em ordem
  /// de prioridade. A checagem de `STORAGE_QUOTA` ocorre antes de `QUOTA`
  /// no bloco de infraestrutura, evitando falso positivo no bloco de
  /// governança.
  ///
  /// Retorna [operational] como fallback para tipos não reconhecidos.
  static AuditEventCategory fromEventType(String eventType) {
    final upper = eventType.toUpperCase();

    // Infraestrutura
    if (upper.contains('POOL_LIMIT') ||
        upper.contains('STORAGE_QUOTA') ||
        upper.contains('SCHEMA') ||
        upper.contains('REPLICATION')) {
      return AuditEventCategory.infrastructure;
    }

    // Governança
    if (upper.contains('PLAN_CHANGED') ||
        upper.contains('QUOTA') ||
        upper.contains('ORG_CREATED') ||
        upper.contains('ORG_ARCHIVED') ||
        upper.contains('ORG_UNARCHIVED')) {
      return AuditEventCategory.governance;
    }

    // Segurança
    if (upper.contains('SECRET') ||
        upper.contains('IMPERSONATION') ||
        upper.contains('MFA') ||
        upper.contains('AUTH')) {
      return AuditEventCategory.security;
    }

    // Fallback
    return AuditEventCategory.operational;
  }

  /// Label em português para exibição na UI.
  String get label => switch (this) {
    AuditEventCategory.infrastructure => 'Infraestrutura',
    AuditEventCategory.governance => 'Governança',
    AuditEventCategory.security => 'Segurança',
    AuditEventCategory.operational => 'Operacional',
  };
}
