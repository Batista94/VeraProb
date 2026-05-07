/// Represents the billing plan tier for a tenant organization.
///
/// INV-4: Pure Dart — zero infrastructure dependencies.
enum PlanType {
  starter,
  professional,
  enterprise;

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case PlanType.starter:
        return 'Starter';
      case PlanType.professional:
        return 'Professional';
      case PlanType.enterprise:
        return 'Enterprise';
    }
  }

  /// The string value stored in the database `plan_type` column.
  String get dbValue => name;

  /// Parses a database value into a [PlanType].
  static PlanType fromDb(String value) {
    return PlanType.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => PlanType.starter,
    );
  }
}
