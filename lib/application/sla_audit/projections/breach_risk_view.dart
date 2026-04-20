/// Read model for SLA breach risk assessment used in presentation layer.
///
/// [riskBps] is int in basis points (0–10000+ where 10000 = 100%).
class BreachRiskView {
  /// Risk magnitude in BPS (e.g. 7500 = 75.00%).
  final int riskBps;
  final String riskLevel;
  final bool requiresPulse;
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;
  final DateTime evaluatedAtUtc;

  const BreachRiskView({
    required this.riskBps,
    required this.riskLevel,
    required this.requiresPulse,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required this.evaluatedAtUtc,
  });
}
