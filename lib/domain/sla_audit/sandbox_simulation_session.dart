import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';

/// Master record for a single SLA Sandbox "What-If" simulation run.
///
/// **INV-4:** All monetary fields are [Money] (BIGINT cents).
/// **INV-6:** All timestamps are UTC.
class SandboxSimulationSession extends Equatable {
  final String id;
  final String organizationId;
  final String contractId;
  final String sessionLabel;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final SandboxSimulationOverrides overridesSnapshot;
  final Money baselineTotalFines;
  final Money simulatedTotalFines;
  final int deltaCents;
  final int? deltaBps;
  final int baselineEventCount;
  final int simulatedCappedEventCount;
  final String createdByUserId;
  final DateTime createdAtUtc;
  final DateTime expiresAtUtc;

  const SandboxSimulationSession({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.sessionLabel,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.overridesSnapshot,
    required this.baselineTotalFines,
    required this.simulatedTotalFines,
    required this.deltaCents,
    this.deltaBps,
    required this.baselineEventCount,
    this.simulatedCappedEventCount = 0,
    required this.createdByUserId,
    required this.createdAtUtc,
    required this.expiresAtUtc,
  });

  factory SandboxSimulationSession.reconstitute({
    required String id,
    required String organizationId,
    required String contractId,
    required String sessionLabel,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required SandboxSimulationOverrides overridesSnapshot,
    required Money baselineTotalFines,
    required Money simulatedTotalFines,
    required int deltaCents,
    int? deltaBps,
    required int baselineEventCount,
    int simulatedCappedEventCount = 0,
    required String createdByUserId,
    required DateTime createdAtUtc,
    required DateTime expiresAtUtc,
  }) {
    if (!periodStartUtc.isUtc ||
        !periodEndUtc.isUtc ||
        !createdAtUtc.isUtc ||
        !expiresAtUtc.isUtc) {
      throw const DomainException('All DateTime fields must be UTC (INV-6).');
    }
    if (!periodEndUtc.isAfter(periodStartUtc)) {
      throw const DomainException('periodEndUtc must be after periodStartUtc.');
    }
    return SandboxSimulationSession(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      sessionLabel: sessionLabel,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      overridesSnapshot: overridesSnapshot,
      baselineTotalFines: baselineTotalFines,
      simulatedTotalFines: simulatedTotalFines,
      deltaCents: deltaCents,
      deltaBps: deltaBps,
      baselineEventCount: baselineEventCount,
      simulatedCappedEventCount: simulatedCappedEventCount,
      createdByUserId: createdByUserId,
      createdAtUtc: createdAtUtc,
      expiresAtUtc: expiresAtUtc,
    );
  }

  factory SandboxSimulationSession.fromRow(Map<String, dynamic> row) {
    final overridesRaw = row['overrides_snapshot'];
    return SandboxSimulationSession.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      contractId: row['contract_id'] as String,
      sessionLabel: row['session_label'] as String,
      periodStartUtc: _parsePostgresUtc(row['period_start_utc']),
      periodEndUtc: _parsePostgresUtc(row['period_end_utc']),
      overridesSnapshot: overridesRaw is Map
          ? SandboxSimulationOverrides.fromJson(
              Map<String, dynamic>.from(overridesRaw),
            )
          : const SandboxSimulationOverrides(),
      baselineTotalFines: Money(
        (row['baseline_total_fines_cents'] as num).toInt(),
      ),
      simulatedTotalFines: Money(
        (row['simulated_total_fines_cents'] as num).toInt(),
      ),
      deltaCents: (row['delta_cents'] as num).toInt(),
      deltaBps: (row['delta_bps'] as num?)?.toInt(),
      baselineEventCount: (row['baseline_event_count'] as num).toInt(),
      simulatedCappedEventCount:
          (row['simulated_capped_event_count'] as num?)?.toInt() ?? 0,
      createdByUserId: row['created_by_user_id'] as String,
      createdAtUtc: _parsePostgresUtc(row['created_at_utc']),
      expiresAtUtc: _parsePostgresUtc(row['expires_at_utc']),
    );
  }

  /// INV-6: naive Postgres timestamps (no Z/offset) are UTC, not local.
  static DateTime _parsePostgresUtc(Object? raw) {
    final s = raw as String;
    final normalized = (s.endsWith('Z') || s.contains('+')) ? s : '${s}Z';
    return DateTime.parse(normalized).toUtc();
  }

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAtUtc);

  @override
  List<Object?> get props => [id];
}
