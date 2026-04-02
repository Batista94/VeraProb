import 'package:equatable/equatable.dart';
import 'domain_exception.dart';

/// Risk level classifications for SLA breach prediction.
///
/// Based on how far the current ETA has entered the 15% safety buffer zone.
enum SlaRiskLevel {
  /// riskPercentage < 0.0 — vehicle is ahead of the buffer window.
  safe,

  /// 0.0 ≤ riskPercentage < 0.5 — entered buffer, low urgency.
  low,

  /// 0.5 ≤ riskPercentage < 0.85 — midway through buffer, escalating.
  moderate,

  /// 0.85 ≤ riskPercentage < 1.0 — near-deadline, triggers pulse animation.
  critical,

  /// riskPercentage ≥ 1.0 — SLA deadline has passed.
  breached,
}

/// Immutable result of a single SLA breach risk evaluation.
///
/// Invariants:
/// - INV-4: zero Flutter/Supabase dependencies.
/// - INV-9: all DateTime fields are UTC.
class SlaBreachRiskReport extends Equatable {
  /// The 15% safety buffer duration for this window.
  final Duration buffer;

  /// Risk ratio relative to the buffer window.
  ///
  /// Negative = comfortably before the buffer.
  /// 0.0 = buffer entry point.
  /// 1.0 = SLA deadline.
  /// > 1.0 = past the deadline (breach).
  final double riskPercentage;

  /// Original trip start time (UTC).
  final DateTime windowStartUtc;

  /// SLA deadline (UTC).
  final DateTime windowEndUtc;

  /// The ETA or event time used for this evaluation (UTC).
  final DateTime evaluatedAtUtc;

  const SlaBreachRiskReport({
    required this.buffer,
    required this.riskPercentage,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required this.evaluatedAtUtc,
  });

  /// Whether the UI should show a pulsing animation (riskPercentage ≥ 0.85).
  bool get requiresPulse => riskPercentage >= 0.85;

  /// Classifies the current risk into a named level.
  SlaRiskLevel get riskLevel {
    if (riskPercentage >= 1.0) return SlaRiskLevel.breached;
    if (riskPercentage >= 0.85) return SlaRiskLevel.critical;
    if (riskPercentage >= 0.50) return SlaRiskLevel.moderate;
    if (riskPercentage >= 0.0) return SlaRiskLevel.low;
    return SlaRiskLevel.safe;
  }

  @override
  List<Object?> get props => [
    buffer,
    riskPercentage,
    windowStartUtc,
    windowEndUtc,
    evaluatedAtUtc,
  ];
}

/// Pure domain service that computes SLA breach risk using the 15% Safety Buffer.
///
/// **The Buffer Rule:** the final 15% of total trip duration is the risk window.
/// When the current ETA enters this window, risk begins escalating from 0.0 to 1.0.
///
/// **Formula:**
/// ```
/// buffer         = (windowEnd − windowStart) × 0.15
/// riskWindowStart = windowEnd − buffer
/// riskPercentage  = (currentEta − riskWindowStart) / buffer
/// ```
///
/// Invariants:
/// - INV-4: zero Flutter/Supabase dependencies.
/// - INV-9: all inputs must be UTC — throws [DomainException] otherwise.
/// - INV-18: pure Dart, WASM-ready.
/// - Deterministic: same inputs → same output.
class SlaBreachRiskCalculator {
  /// Fraction of total trip duration used as the safety buffer (15%).
  static const double bufferFraction = 0.15;

  /// Lower bound of the critical zone (triggers pulse animation).
  static const double criticalThreshold = 0.85;

  /// Lower bound of the moderate zone.
  static const double moderateThreshold = 0.50;

  const SlaBreachRiskCalculator();

  /// Evaluates breach risk for a single SLA window.
  ///
  /// [windowStartUtc] — trip start time (UTC).
  /// [windowEndUtc]   — SLA deadline (UTC). Must be strictly after [windowStartUtc].
  /// [currentEtaUtc]  — current ETA or evaluation timestamp (UTC).
  ///
  /// Throws [DomainException] when:
  /// - any DateTime is not UTC (INV-9).
  /// - [windowEndUtc] is not strictly after [windowStartUtc].
  SlaBreachRiskReport evaluate({
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
    required DateTime currentEtaUtc,
  }) {
    _assertUtc(windowStartUtc, 'windowStartUtc');
    _assertUtc(windowEndUtc, 'windowEndUtc');
    _assertUtc(currentEtaUtc, 'currentEtaUtc');

    final totalSeconds = windowEndUtc.difference(windowStartUtc).inSeconds;
    if (totalSeconds <= 0) {
      throw DomainException(
        'windowEndUtc must be strictly after windowStartUtc, got $totalSeconds seconds',
      );
    }

    final bufferSeconds = (totalSeconds * bufferFraction).round();
    final riskWindowStart = windowEndUtc.subtract(
      Duration(seconds: bufferSeconds),
    );
    final elapsedIntoBuffer = currentEtaUtc
        .difference(riskWindowStart)
        .inSeconds;
    final riskPercentage = elapsedIntoBuffer / bufferSeconds;

    return SlaBreachRiskReport(
      buffer: Duration(seconds: bufferSeconds),
      riskPercentage: riskPercentage,
      windowStartUtc: windowStartUtc,
      windowEndUtc: windowEndUtc,
      evaluatedAtUtc: currentEtaUtc,
    );
  }

  void _assertUtc(DateTime dt, String fieldName) {
    if (!dt.isUtc) {
      throw DomainException(
        '$fieldName must be UTC (INV-9), received isUtc=false',
      );
    }
  }
}
