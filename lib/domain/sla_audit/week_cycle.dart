/// Recurrence cycle type for industrial contractual shift patterns.
///
/// Supports up to 4-week rotating schedules (common in Brazilian fretamento
/// and industrial shift contracts). The cycle is always evaluated as a
/// 4-week modular window anchored to [PlanDeclaration.cycleAnchorDateUtc].
///
/// **Mapping to modular arithmetic:**
/// - [everyWeek]  → no filtering; runs on every matching weekday
/// - [weekA]      → fires when `weeksSinceAnchor % 4 == 0`
/// - [weekB]      → fires when `weeksSinceAnchor % 4 == 1`
/// - [weekC]      → fires when `weeksSinceAnchor % 4 == 2`
/// - [weekD]      → fires when `weeksSinceAnchor % 4 == 3`
///
/// For 2-week alternating contracts, use [weekA] + [weekB] patterns (each
/// fires once every 4 weeks, yielding alternating coverage within the pair).
enum WeekCycle {
  everyWeek,
  weekA,
  weekB,
  weekC,
  weekD;

  /// Serializes to JSON string for JSONB storage.
  String toJson() => name;

  /// Deserializes from JSON. Returns [everyWeek] for null or unknown values
  /// (backward compat — plans created before this field existed).
  static WeekCycle fromJson(String? value) {
    if (value == null) return WeekCycle.everyWeek;
    return WeekCycle.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WeekCycle.everyWeek,
    );
  }
}
