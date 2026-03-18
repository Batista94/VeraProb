import 'package:equatable/equatable.dart';

import '../../../domain/sla_audit/execution_status.dart';
import '../../../domain/sla_audit/operational_alert.dart';
import 'sla_execution_item_view.dart';

/// Defines the severity of a node in the dashboard risk feed.
enum DashboardFeedSeverity { critical, warning, pending, onTime }

/// A read model node representing a single contractual obligation (SET)
/// evaluated alongside its active operational alerts for the dashboard.
class DashboardRiskFeedNode extends Equatable {
  final SlaExecutionItemView execution;
  final List<OperationalAlert> activeAlerts;
  final DashboardFeedSeverity severity;

  const DashboardRiskFeedNode({
    required this.execution,
    required this.activeAlerts,
    required this.severity,
  });

  factory DashboardRiskFeedNode.evaluate(
    SlaExecutionItemView execution,
    List<OperationalAlert> alerts,
  ) {
    DashboardFeedSeverity derivedSeverity = DashboardFeedSeverity.onTime;

    if (execution.status == ExecutionStatus.noShow ||
        execution.status == ExecutionStatus.evidenceGap) {
      derivedSeverity = DashboardFeedSeverity.critical;
    } else if (alerts.any((a) => a.severity == 'CRITICAL')) {
      derivedSeverity = DashboardFeedSeverity.critical;
    } else if (alerts.any((a) => a.severity == 'WARNING')) {
      derivedSeverity = DashboardFeedSeverity.warning;
    } else if (execution.status == ExecutionStatus.pending) {
      derivedSeverity = DashboardFeedSeverity.pending;
    }

    return DashboardRiskFeedNode(
      execution: execution,
      activeAlerts: alerts,
      severity: derivedSeverity,
    );
  }

  @override
  List<Object?> get props => [execution, activeAlerts, severity];
}
