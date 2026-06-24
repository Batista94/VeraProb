import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/sla_audit/sla_breach_risk_calculator.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'analytics_providers.dart';
import 'auth_providers.dart';

// ── At-Risk SLA Count ────────────────────────────────────────────────────────

/// Count of active SLA windows in the CRITICAL or BREACHED zone
/// (`riskBps >= 8500`). Used by the KPI bar "SLA em Risco" chip.
///
/// Server-backed (Sprint C): risk is computed by `get_fleet_risk_summary`
/// byte-identically to [SlaBreachRiskCalculator] (INV-15), replacing the prior
/// in-app per-row loop. Returns 0 when unauthenticated.
final atRiskSlaCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) return 0;

  final windows = await ref
      .watch(fleetRiskQueryServiceProvider)
      .listFleetRisk(organizationId: organizationId, limit: 500)
      .withProviderTimeout();

  return windows
      .where((w) => w.riskBps >= SlaBreachRiskCalculator.criticalThresholdBps)
      .length;
});
