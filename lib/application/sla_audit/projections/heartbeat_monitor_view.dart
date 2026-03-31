import 'package:equatable/equatable.dart';

import '../../../domain/sla_audit/heartbeat_classification.dart';

/// Read model: fleet-level heartbeat health snapshot.
///
/// Produced by [HeartbeatQueryService] and consumed by the UI (INV-23 read-only).
/// All device entries carry their individual [DeviceHeartbeatStatus].
/// Counts are pre-computed for O(1) display in OCC widgets.
class HeartbeatMonitorView extends Equatable {
  final List<DeviceHeartbeatStatus> devices;

  /// Number of devices classified as [HeartbeatClassification.deviceTamper].
  final int tamperCount;

  /// Number of devices classified as [HeartbeatClassification.networkIssue].
  final int networkIssueCount;

  /// Number of devices classified as [HeartbeatClassification.normal].
  final int normalCount;

  /// Number of devices classified as [HeartbeatClassification.unknown].
  final int unknownCount;

  const HeartbeatMonitorView({
    required this.devices,
    required this.tamperCount,
    required this.networkIssueCount,
    required this.normalCount,
    required this.unknownCount,
  });

  /// Total number of devices tracked.
  int get totalCount => devices.length;

  /// True if any device is classified as tamper or unknown.
  bool get hasAlerts => tamperCount > 0 || unknownCount > 0;

  @override
  List<Object?> get props => [
    devices,
    tamperCount,
    networkIssueCount,
    normalCount,
    unknownCount,
  ];
}
