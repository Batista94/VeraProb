import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/shared/postgres_utc.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Per-event A/B comparison row in the Shadow Ledger.
///
/// One row per original penal ledger entry, re-evaluated under hypothetical rules.
class SandboxSimulationResult extends Equatable {
  final String id;
  final String sessionId;
  final String organizationId;
  final String sourceLedgerEntryId;
  final String sourceEventType;
  final DateTime occurredAtUtc;
  final Money baselineFine;
  final Map<String, dynamic> baselineRuleSnapshot;
  final Money simulatedFine;
  final Map<String, dynamic> simulatedRuleApplied;
  final bool wasOverrideApplied;
  final bool baselineCapTruncated;
  final bool simulatedCapTruncated;
  final DateTime createdAtUtc;

  const SandboxSimulationResult({
    required this.id,
    required this.sessionId,
    required this.organizationId,
    required this.sourceLedgerEntryId,
    required this.sourceEventType,
    required this.occurredAtUtc,
    required this.baselineFine,
    required this.baselineRuleSnapshot,
    required this.simulatedFine,
    required this.simulatedRuleApplied,
    required this.wasOverrideApplied,
    this.baselineCapTruncated = false,
    this.simulatedCapTruncated = false,
    required this.createdAtUtc,
  });

  factory SandboxSimulationResult.reconstitute({
    required String id,
    required String sessionId,
    required String organizationId,
    required String sourceLedgerEntryId,
    required String sourceEventType,
    required DateTime occurredAtUtc,
    required Money baselineFine,
    required Map<String, dynamic> baselineRuleSnapshot,
    required Money simulatedFine,
    required Map<String, dynamic> simulatedRuleApplied,
    required bool wasOverrideApplied,
    bool baselineCapTruncated = false,
    bool simulatedCapTruncated = false,
    required DateTime createdAtUtc,
  }) {
    if (!occurredAtUtc.isUtc || !createdAtUtc.isUtc) {
      throw const DomainException('All DateTime fields must be UTC (INV-6).');
    }
    return SandboxSimulationResult(
      id: id,
      sessionId: sessionId,
      organizationId: organizationId,
      sourceLedgerEntryId: sourceLedgerEntryId,
      sourceEventType: sourceEventType,
      occurredAtUtc: occurredAtUtc,
      baselineFine: baselineFine,
      baselineRuleSnapshot: Map.unmodifiable(baselineRuleSnapshot),
      simulatedFine: simulatedFine,
      simulatedRuleApplied: Map.unmodifiable(simulatedRuleApplied),
      wasOverrideApplied: wasOverrideApplied,
      baselineCapTruncated: baselineCapTruncated,
      simulatedCapTruncated: simulatedCapTruncated,
      createdAtUtc: createdAtUtc,
    );
  }

  factory SandboxSimulationResult.fromRow(Map<String, dynamic> row) {
    return SandboxSimulationResult.reconstitute(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      organizationId: row['organization_id'] as String,
      sourceLedgerEntryId: row['source_ledger_entry_id'] as String,
      sourceEventType: row['source_event_type'] as String,
      occurredAtUtc: parsePostgresUtc(row['occurred_at_utc']),
      baselineFine: Money((row['baseline_fine_cents'] as num).toInt()),
      baselineRuleSnapshot: Map<String, dynamic>.from(
        row['baseline_rule_snapshot'] as Map? ?? const {},
      ),
      simulatedFine: Money((row['simulated_fine_cents'] as num).toInt()),
      simulatedRuleApplied: Map<String, dynamic>.from(
        row['simulated_rule_applied'] as Map? ?? const {},
      ),
      wasOverrideApplied: row['was_override_applied'] as bool,
      baselineCapTruncated: row['baseline_cap_truncated'] as bool? ?? false,
      simulatedCapTruncated: row['simulated_cap_truncated'] as bool? ?? false,
      createdAtUtc: parsePostgresUtc(row['created_at_utc']),
    );
  }

  int get fineDeltaCents => baselineFine.cents - simulatedFine.cents;

  @override
  List<Object?> get props => [id];
}
