import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/command_center/models/driver_alert_group.dart';

/// Groups a flat list of alerts by driver_id from the alert context.
///
/// Alerts without driver_id are grouped under a synthetic "unknown" group.
/// Groups are sorted: CRITICAL first, then by alert count descending.
/// Within each group, alerts are sorted by triggeredAtUtc descending.
List<DriverAlertGroup> groupAlertsByDriver(List<OperationalAlert> alerts) {
  final Map<String, List<OperationalAlert>> grouped = {};

  for (final alert in alerts) {
    final driverId = alert.context['driver_id'] as String? ?? '_unknown';
    (grouped[driverId] ??= []).add(alert);
  }

  final groups = grouped.entries.map((entry) {
    final driverId = entry.key;
    final driverAlerts = entry.value
      ..sort((a, b) => b.triggeredAtUtc.compareTo(a.triggeredAtUtc));

    final driverName = driverAlerts
        .map((a) => a.context['driver_name'] as String?)
        .firstWhere((n) => n != null, orElse: () => null);

    return DriverAlertGroup(
      driverId: driverId,
      driverName: driverId == '_unknown' ? null : driverName,
      contractHealth: _deriveHealth(driverAlerts),
      alerts: driverAlerts,
    );
  }).toList();

  groups.sort((a, b) {
    final healthCmp = a.contractHealth.index.compareTo(b.contractHealth.index);
    // critical (2) > yellow (1) > green (0) — reverse for critical-first
    if (healthCmp != 0) return -healthCmp;
    return b.count.compareTo(a.count);
  });

  return groups;
}

ContractHealthStatus _deriveHealth(List<OperationalAlert> alerts) {
  for (final a in alerts) {
    if (a.severity == 'CRITICAL') return ContractHealthStatus.critical;
  }
  for (final a in alerts) {
    if (a.severity == 'HIGH') return ContractHealthStatus.yellow;
  }
  return ContractHealthStatus.green;
}
