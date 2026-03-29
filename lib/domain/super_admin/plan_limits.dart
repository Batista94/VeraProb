import 'plan_type.dart';

/// Default quota limits per [PlanType].
///
/// These are the values auto-filled by [CreateOrganizationHandler] when the
/// caller does not supply explicit limits.  DB-level triggers enforce the same
/// boundaries so no client-side bypass is possible (INV-1, INV-19).
///
/// All limits are integer counts (INV-19: never Money).
/// `null` means unlimited (enterprise).
typedef PlanQuota = ({int? maxVehicles, int? maxContracts});

abstract final class PlanLimits {
  static const Map<PlanType, PlanQuota> defaults = {
    PlanType.starter: (maxVehicles: 10, maxContracts: 5),
    PlanType.professional: (maxVehicles: 100, maxContracts: 50),
    PlanType.enterprise: (maxVehicles: null, maxContracts: null),
  };

  /// Returns the max vehicles for [planType], or `null` for unlimited.
  static int? maxVehicles(PlanType planType) =>
      defaults[planType]!.maxVehicles;

  /// Returns the max active contracts for [planType], or `null` for unlimited.
  static int? maxContracts(PlanType planType) =>
      defaults[planType]!.maxContracts;
}
