import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';

/// Direction of the financial delta between baseline and simulated fines.
enum SandboxDeltaDirection { savings, increase, neutral }

/// Session-level A/B comparison aggregate (baseline vs simulated).
///
/// [deltaCents] is positive when simulated fines are **lower** than baseline
/// (projected savings). Matches the SQL convention in `sandbox_simulation_sessions`.
class SandboxSimulationDelta extends Equatable {
  final Money baselineTotalFines;
  final Money simulatedTotalFines;
  final int deltaCents;
  final int? deltaBps;
  final int baselineEventCount;
  final int simulatedCappedEventCount;

  const SandboxSimulationDelta({
    required this.baselineTotalFines,
    required this.simulatedTotalFines,
    required this.deltaCents,
    this.deltaBps,
    required this.baselineEventCount,
    this.simulatedCappedEventCount = 0,
  });

  Money get deltaAmount => Money(deltaCents.abs());

  SandboxDeltaDirection get direction {
    if (deltaCents > 0) return SandboxDeltaDirection.savings;
    if (deltaCents < 0) return SandboxDeltaDirection.increase;
    return SandboxDeltaDirection.neutral;
  }

  factory SandboxSimulationDelta.fromSession(SandboxSimulationSession session) {
    return SandboxSimulationDelta(
      baselineTotalFines: session.baselineTotalFines,
      simulatedTotalFines: session.simulatedTotalFines,
      deltaCents: session.deltaCents,
      deltaBps: session.deltaBps,
      baselineEventCount: session.baselineEventCount,
      simulatedCappedEventCount: session.simulatedCappedEventCount,
    );
  }

  @override
  List<Object?> get props => [
    baselineTotalFines,
    simulatedTotalFines,
    deltaCents,
    deltaBps,
    baselineEventCount,
    simulatedCappedEventCount,
  ];
}
