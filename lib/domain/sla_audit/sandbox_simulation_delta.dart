import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';

/// Direction of the financial delta between baseline and simulated fines.
enum SandboxDeltaDirection { savings, increase, neutral }

/// Session-level A/B helpers (baseline vs simulated).
///
/// [deltaCents] is positive when simulated fines are **lower** than baseline
/// (projected savings). Matches the SQL convention in `sandbox_simulation_sessions`.
extension SandboxSimulationSessionDelta on SandboxSimulationSession {
  Money get deltaAmount => Money(deltaCents.abs());

  SandboxDeltaDirection get direction {
    if (deltaCents > 0) return SandboxDeltaDirection.savings;
    if (deltaCents < 0) return SandboxDeltaDirection.increase;
    return SandboxDeltaDirection.neutral;
  }
}
