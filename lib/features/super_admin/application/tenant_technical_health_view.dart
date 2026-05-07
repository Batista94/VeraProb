/// Status visual unificado para indicadores de pulsação.
///
/// Mapeia estados de saúde técnica para cores da paleta VeraProbColors:
/// - [healthy] → `VeraProbColors.success` (verde)
/// - [warning] → `VeraProbColors.warning` (amarelo)
/// - [critical] → `VeraProbColors.error` (vermelho)
enum PulseStatus { healthy, warning, critical }

/// Status de replicação de dados de um tenant.
///
/// Valores correspondem às strings retornadas pelo backend:
/// `healthy`, `delayed`, `failed`, `unknown`.
enum ReplicationStatus {
  healthy,
  delayed,
  failed,
  unknown;

  /// Converte uma string do backend para o enum correspondente.
  /// Retorna [unknown] para valores não reconhecidos.
  static ReplicationStatus fromString(String value) {
    return ReplicationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReplicationStatus.unknown,
    );
  }

  /// Mapeia para [PulseStatus] para uso no [PulseIndicator].
  PulseStatus toPulseStatus() => switch (this) {
    ReplicationStatus.healthy => PulseStatus.healthy,
    ReplicationStatus.delayed => PulseStatus.warning,
    ReplicationStatus.failed => PulseStatus.critical,
    ReplicationStatus.unknown => PulseStatus.critical,
  };
}

/// Status de integridade de schema de um tenant.
///
/// Valores do backend usam snake_case: `compliant`, `minor_drift`,
/// `critical_drift`, `unknown`.
enum SchemaIntegrityStatus {
  compliant,
  minorDrift,
  criticalDrift,
  unknown;

  /// Converte uma string snake_case do backend para o enum correspondente.
  /// Usa switch expression para tratar `minor_drift` e `critical_drift`.
  /// Retorna [unknown] para valores não reconhecidos.
  static SchemaIntegrityStatus fromString(String value) {
    return switch (value) {
      'compliant' => SchemaIntegrityStatus.compliant,
      'minor_drift' => SchemaIntegrityStatus.minorDrift,
      'critical_drift' => SchemaIntegrityStatus.criticalDrift,
      _ => SchemaIntegrityStatus.unknown,
    };
  }

  /// Mapeia para [PulseStatus] para uso no [PulseIndicator].
  PulseStatus toPulseStatus() => switch (this) {
    SchemaIntegrityStatus.compliant => PulseStatus.healthy,
    SchemaIntegrityStatus.minorDrift => PulseStatus.warning,
    SchemaIntegrityStatus.criticalDrift => PulseStatus.critical,
    SchemaIntegrityStatus.unknown => PulseStatus.critical,
  };
}

/// ViewModel de saúde técnica de um tenant para a camada de apresentação.
///
/// Contém status de replicação, integridade de schema, versão do schema
/// e timestamp da última verificação.
///
/// **INV-4:** Apenas tipos primitivos e enums — sem tipos de domínio.
/// **INV-11:** Construtor `const`.
class TenantTechnicalHealthView {
  final ReplicationStatus replicationStatus;
  final SchemaIntegrityStatus schemaIntegrityStatus;
  final String schemaVersion;
  final DateTime? lastCheckAt;

  const TenantTechnicalHealthView({
    required this.replicationStatus,
    required this.schemaIntegrityStatus,
    required this.schemaVersion,
    this.lastCheckAt,
  });

  /// Cria uma instância a partir de um mapa JSON retornado pelo backend.
  ///
  /// Campos ausentes ou nulos recebem valores padrão seguros:
  /// - `replication_status` → [ReplicationStatus.unknown]
  /// - `schema_integrity_status` → [SchemaIntegrityStatus.unknown]
  /// - `schema_version` → `'unknown'`
  /// - `last_check_at` → `null`
  factory TenantTechnicalHealthView.fromJson(Map<String, Object?> json) {
    return TenantTechnicalHealthView(
      replicationStatus: ReplicationStatus.fromString(
        json['replication_status'] as String? ?? 'unknown',
      ),
      schemaIntegrityStatus: SchemaIntegrityStatus.fromString(
        json['schema_integrity_status'] as String? ?? 'unknown',
      ),
      schemaVersion: json['schema_version'] as String? ?? 'unknown',
      lastCheckAt: json['last_check_at'] != null
          ? DateTime.parse(json['last_check_at'] as String)
          : null,
    );
  }
}
