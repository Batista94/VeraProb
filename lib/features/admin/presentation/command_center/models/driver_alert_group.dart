import 'package:veraprob/domain/sla_audit/operational_alert.dart';

/// Health status of a driver's contract relationship.
enum ContractHealthStatus {
  /// All alerts are WARNING or lower.
  green,

  /// At least one HIGH alert.
  yellow,

  /// At least one CRITICAL alert.
  critical,
}

/// A group of alerts belonging to the same driver.
///
/// Used by the Command Center drawer to render expandable driver cards.
class DriverAlertGroup {
  final String driverId;
  final String? driverName;
  final ContractHealthStatus contractHealth;
  final List<OperationalAlert> alerts;

  const DriverAlertGroup({
    required this.driverId,
    required this.driverName,
    required this.contractHealth,
    required this.alerts,
  });

  /// The highest-severity alert in this group (for sort ordering).
  OperationalAlert get highestSeverityAlert => alerts.first;

  /// Total alert count for the badge.
  int get count => alerts.length;
}
