import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/presentation/sandbox/widgets/dashboard/sandbox_delta_bps.dart';

/// Aggregated A/B fines for a single ledger event / rule type bucket.
class SandboxRuleBreakdownRow extends Equatable {
  final String ruleType;
  final int baselineCents;
  final int simulatedCents;
  final int eventCount;

  const SandboxRuleBreakdownRow({
    required this.ruleType,
    required this.baselineCents,
    required this.simulatedCents,
    required this.eventCount,
  });

  int get deltaCents => baselineCents - simulatedCents;

  int? get deltaBps => SandboxDeltaBps.compute(
    baselineCents: baselineCents,
    simulatedCents: simulatedCents,
  );

  /// Groups [results] by [SandboxSimulationResult.sourceEventType].
  static List<SandboxRuleBreakdownRow> fromResults(
    List<SandboxSimulationResult> results,
  ) {
    final map = <String, SandboxRuleBreakdownRow>{};
    for (final r in results) {
      final key = r.sourceEventType;
      final existing = map[key];
      if (existing == null) {
        map[key] = SandboxRuleBreakdownRow(
          ruleType: key,
          baselineCents: r.baselineFine.cents,
          simulatedCents: r.simulatedFine.cents,
          eventCount: 1,
        );
      } else {
        map[key] = SandboxRuleBreakdownRow(
          ruleType: key,
          baselineCents: existing.baselineCents + r.baselineFine.cents,
          simulatedCents: existing.simulatedCents + r.simulatedFine.cents,
          eventCount: existing.eventCount + 1,
        );
      }
    }
    final rows = map.values.toList()
      ..sort((a, b) => a.ruleType.compareTo(b.ruleType));
    return rows;
  }

  @override
  List<Object?> get props => [
    ruleType,
    baselineCents,
    simulatedCents,
    eventCount,
  ];
}
