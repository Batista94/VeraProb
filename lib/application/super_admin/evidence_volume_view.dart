/// ViewModel de volumetria de evidências de um tenant para a camada de
/// apresentação.
///
/// Contém o total histórico de evidências e o total do mês corrente,
/// consumidos a partir de uma materialized view (`mv_evidence_volume`)
/// via Edge Function proxy.
///
/// **INV-4:** Apenas tipos primitivos — sem tipos de domínio.
/// **INV-11:** Construtor `const`.
class EvidenceVolumeView {
  /// Total acumulado de evidências desde a criação do tenant.
  final int totalHistorical;

  /// Total de evidências registradas no mês corrente.
  final int totalMonthly;

  const EvidenceVolumeView({
    required this.totalHistorical,
    required this.totalMonthly,
  });

  /// Cria uma instância a partir de um mapa JSON retornado pelo backend.
  ///
  /// Campos ausentes ou nulos recebem fallback para `0`:
  /// - `total_historical` → `0`
  /// - `total_monthly` → `0`
  factory EvidenceVolumeView.fromJson(Map<String, Object?> json) {
    return EvidenceVolumeView(
      totalHistorical: (json['total_historical'] as num?)?.toInt() ?? 0,
      totalMonthly: (json['total_monthly'] as num?)?.toInt() ?? 0,
    );
  }
}
