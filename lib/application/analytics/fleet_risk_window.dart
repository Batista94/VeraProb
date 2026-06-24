import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sla_breach_risk_calculator.dart';

/// A single active SLA execution window with its server-computed breach risk.
///
/// Projected by the `get_fleet_risk_summary` RPC. [riskBps] is computed in SQL
/// byte-identically to [SlaBreachRiskCalculator] (INV-15): the client never
/// recomputes it from the wire — it just renders it.
class FleetRiskWindow extends Equatable {
  final String setId;
  final String contractId;
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;

  /// Server-computed risk in basis points (<0 safe, 8500 critical, ≥10000 breach).
  final int riskBps;
  final Money contractualValue;

  const FleetRiskWindow({
    required this.setId,
    required this.contractId,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required this.riskBps,
    required this.contractualValue,
  });

  factory FleetRiskWindow.fromJson(Map<String, dynamic> json) {
    DateTime parseUtc(Object? v) => DateTime.parse(v as String).toUtc();
    return FleetRiskWindow(
      setId: json['set_id'] as String,
      contractId: json['contract_id'] as String,
      windowStartUtc: parseUtc(json['window_start_utc']),
      windowEndUtc: parseUtc(json['window_end_utc']),
      riskBps: (json['risk_bps'] as num).toInt(),
      contractualValue: Money((json['contractual_value_cents'] as num).toInt()),
    );
  }

  /// Adapts this window to a [SlaBreachRiskReport] for the existing
  /// `RiskThermometerWidget`. Uses the SERVER [riskBps] (authoritative); the
  /// 15% buffer is reconstructed with the same formula for completeness (the
  /// widget renders from [riskBps]/`riskLevel` only).
  SlaBreachRiskReport asBreachReport({required DateTime nowUtc}) {
    final totalSeconds = windowEndUtc.difference(windowStartUtc).inSeconds;
    final bufferSeconds = totalSeconds > 0
        ? ((totalSeconds * SlaBreachRiskCalculator.bufferFractionBps) + 5000) ~/
              10000
        : 0;
    return SlaBreachRiskReport(
      buffer: Duration(seconds: bufferSeconds),
      riskBps: riskBps,
      windowStartUtc: windowStartUtc,
      windowEndUtc: windowEndUtc,
      evaluatedAtUtc: nowUtc,
    );
  }

  @override
  List<Object?> get props => [
    setId,
    contractId,
    windowStartUtc,
    windowEndUtc,
    riskBps,
    contractualValue,
  ];
}
