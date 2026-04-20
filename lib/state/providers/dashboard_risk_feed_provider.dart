import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/dashboard_risk_feed_node.dart';
import 'alert_providers.dart';
import 'auth_providers.dart';
import 'sla_providers.dart';

/// Provides a reactive, read-only feed of today's contractual obligations
/// joined with their active alerts, ordered by severity.
///
/// Implements CQRS: Does not calculate risk, merely projects
/// existing states and alerts into the [DashboardRiskFeedNode] model.
final dashboardRiskFeedProvider = FutureProvider<List<DashboardRiskFeedNode>>((
  ref,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);

  if (organizationId == null) {
    return [];
  }

  // 1. Fetch active alerts across the tenant
  final activeAlerts = await ref.watch(activeAlertsProvider.future);

  // 2. Fetch today's execution states
  final queryService = ref.watch(slaExecutionQueryServiceProvider);

  // Determine "today" boundaries in local time, then convert to UTC bounds
  // (Assuming application runs in a stable timezone approach, or simple UTC boundary for now)
  final now = DateTime.now().toUtc();
  final startOfDay = DateTime(now.year, now.month, now.day).toUtc();
  final endOfDay = startOfDay.add(const Duration(days: 1));

  final todaysExecutions = await queryService.listByWindow(
    startOfDay,
    endOfDay,
    organizationId: organizationId,
  );

  // 3. Join executions with alerts and map to Feed Nodes
  final nodes = todaysExecutions.map((exec) {
    final relatedAlerts = activeAlerts
        .where((a) => a.entityId == exec.setId)
        .toList();
    return DashboardRiskFeedNode.evaluate(exec, relatedAlerts);
  }).toList();

  // 4. Sort strictly by severity (CRITICAL > WARNING > PENDING > ON_TIME)
  // then chronologically
  nodes.sort((a, b) {
    final severityComparison = a.severity.index.compareTo(b.severity.index);
    if (severityComparison != 0) {
      return severityComparison;
    }
    return a.execution.windowStartUtc.compareTo(b.execution.windowStartUtc);
  });

  return nodes;
});
