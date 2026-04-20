/// Enum representing the transport vertical (business segment) for SLA templates.
///
/// Each vertical carries domain-specific penalty defaults via [SmartDefaults].
/// Pure Dart — no infrastructure dependencies (INV-18).
enum TransportVertical {
  fretamento,
  cargaSeca,
  cargaRefrigerada,
  transferenciaFuncionarios,
  escolar,
  custom;

  /// Returns the UI label in Brazilian Portuguese.
  String get label => switch (this) {
    TransportVertical.fretamento => 'Fretamento',
    TransportVertical.cargaSeca => 'Carga Seca',
    TransportVertical.cargaRefrigerada => 'Carga Refrigerada',
    TransportVertical.transferenciaFuncionarios =>
      'Transferência de Funcionários',
    TransportVertical.escolar => 'Escolar',
    TransportVertical.custom => 'Personalizado',
  };

  static TransportVertical fromJson(String? value) {
    return TransportVertical.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TransportVertical.custom,
    );
  }

  String toJson() => name;
}
