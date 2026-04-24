import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/dashboard_risk_feed_node.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1);

  SlaExecutionItemView makeExecution(ExecutionStatus status) =>
      SlaExecutionItemView(
        setId: 's1',
        contractId: 'c1',
        status: status,
        windowStartUtc: now,
        windowEndUtc: now.add(const Duration(hours: 1)),
        startLatitude: -23.5,
        startLongitude: -46.6,
        startRadiusMeters: 100,
        contractualValue: 50000,
        noShowPenaltyBps: 10000,
      );

  OperationalAlert makeAlert(String severity) => OperationalAlert(
    id: 'alert-1',
    organizationId: 'org-1',
    entityId: 's1',
    contractId: 'c1',
    alertType: 'TEST',
    severity: severity,
    triggeredAtUtc: now,
  );

  group('DashboardRiskFeedNode.evaluate severity', () {
    test('noShow status → critical severity', () {
      final node = DashboardRiskFeedNode.evaluate(
        makeExecution(ExecutionStatus.failed),
        [],
      );
      expect(node.severity, DashboardFeedSeverity.critical);
    });

    test('evidenceGap status → critical severity', () {
      final node = DashboardRiskFeedNode.evaluate(
        makeExecution(ExecutionStatus.completedWithGaps),
        [],
      );
      expect(node.severity, DashboardFeedSeverity.critical);
    });

    test('pending execution + CRITICAL alert → critical severity', () {
      final node = DashboardRiskFeedNode.evaluate(
        makeExecution(ExecutionStatus.planned),
        [makeAlert('CRITICAL')],
      );
      expect(node.severity, DashboardFeedSeverity.critical);
    });

    test('pending execution + WARNING alert → warning severity', () {
      final node = DashboardRiskFeedNode.evaluate(
        makeExecution(ExecutionStatus.planned),
        [makeAlert('WARNING')],
      );
      expect(node.severity, DashboardFeedSeverity.warning);
    });

    test('pending execution + no alerts → pending severity', () {
      final node = DashboardRiskFeedNode.evaluate(
        makeExecution(ExecutionStatus.planned),
        [],
      );
      expect(node.severity, DashboardFeedSeverity.pending);
    });

    test('executed + no alerts → onTime severity', () {
      final node = DashboardRiskFeedNode.evaluate(
        makeExecution(ExecutionStatus.completed),
        [],
      );
      expect(node.severity, DashboardFeedSeverity.onTime);
    });

    test('stores execution and alerts on the node', () {
      final exec = makeExecution(ExecutionStatus.completed);
      final alert = makeAlert('WARNING');
      final node = DashboardRiskFeedNode.evaluate(exec, [alert]);
      expect(node.execution, exec);
      expect(node.activeAlerts, [alert]);
    });
  });
}
