/// Operational lifecycle status of an asset (vehicle/equipment).
///
/// Driven by domain events (state machine) — never set directly.
/// Only [active] assets are evaluated for SLA compliance.
/// [maintenance] and [offDuty] suppress penalty generation (INV-13).
enum AssetStatus {
  /// Asset is operational and eligible for SLA evaluation.
  active,

  /// Asset is in a scheduled or unscheduled maintenance state.
  /// SLA violations are suppressed — no false positives from downtime.
  maintenance,

  /// Asset is intentionally offline (end-of-shift, seasonal removal, etc.).
  /// SLA violations are suppressed.
  offDuty,
}
