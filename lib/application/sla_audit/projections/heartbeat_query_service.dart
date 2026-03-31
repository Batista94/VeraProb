import 'heartbeat_monitor_view.dart';

/// Abstract query service for the Heartbeat Monitor projection.
///
/// Implementations compute per-device gap seconds and fleet active ratio
/// from [canonical_facts], then delegate classification to [HeartbeatClassifier].
///
/// Scoped per [organizationId] (INV-1).
abstract class HeartbeatQueryService {
  /// Returns the current heartbeat health snapshot for [organizationId].
  Future<HeartbeatMonitorView> getHeartbeatMonitor({
    required String organizationId,
  });
}
