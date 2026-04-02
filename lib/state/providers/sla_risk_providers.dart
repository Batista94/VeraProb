import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sla_audit/execution_status.dart';
import '../../domain/sla_audit/sla_breach_risk_calculator.dart';
import 'auth_providers.dart';
import 'sla_providers.dart';

// ── At-Risk SLA Count ────────────────────────────────────────────────────────

/// Count of today's pending SLA windows in the CRITICAL or BREACHED zone.
///
/// Used by the KPI bar "SLA em Risco" chip. Recalculates against live clock
/// (INV-9: [currentEtaUtc] = [DateTime.now().toUtc()]).
///
/// Returns 0 when [organizationId] is null (unauthenticated state).
final atRiskSlaCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return 0;

  final queryService = ref.watch(slaExecutionQueryServiceProvider);
  final now = DateTime.now().toUtc();
  final todayUtc = DateTime.utc(now.year, now.month, now.day);

  final pending = await queryService.listByStatus(
    ExecutionStatus.pending,
    organizationId: organizationId,
  );

  const calculator = SlaBreachRiskCalculator();
  int count = 0;
  for (final e in pending) {
    if (!e.windowStartUtc.isAfter(todayUtc)) continue;
    final report = calculator.evaluate(
      windowStartUtc: e.windowStartUtc,
      windowEndUtc: e.windowEndUtc,
      currentEtaUtc: now,
    );
    if (report.requiresPulse) count++;
  }
  return count;
});
