/// Enum representing the required vehicle category in a contractual shift pattern.
///
/// This is a contractual clause — the engine uses it to detect downgrades and
/// apply [SLAPenalties.downgradePenaltyFlat] when the actual vehicle category
/// is inferior to the contracted one.
enum VehicleCategory {
  conventional,
  executive,
  micro,
  van,
  accessible;

  /// Returns the UI label in Brazilian Portuguese.
  String get label => switch (this) {
        VehicleCategory.conventional => 'Convencional',
        VehicleCategory.executive => 'Executivo',
        VehicleCategory.micro => 'Micro-ônibus',
        VehicleCategory.van => 'Van',
        VehicleCategory.accessible => 'Acessível (PCD)',
      };

  static VehicleCategory fromJson(String? value) {
    return VehicleCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => VehicleCategory.conventional,
    );
  }

  String toJson() => name;
}
