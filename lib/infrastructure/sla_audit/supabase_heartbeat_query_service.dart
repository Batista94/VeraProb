import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sla_audit/projections/heartbeat_monitor_view.dart';
import '../../application/sla_audit/projections/heartbeat_query_service.dart';
import '../../domain/sla_audit/heartbeat_classification.dart';
import '../../domain/sla_audit/heartbeat_classifier.dart';

/// Supabase implementation of [HeartbeatQueryService].
///
/// Calls the security-definer RPC [get_device_heartbeat_status] which
/// returns rows from [vw_device_heartbeat_status] scoped to [organizationId].
/// Classification is performed in the domain layer (INV-18).
///
/// INV-1: organization_id is always passed as an explicit parameter — never
///        derived from client-side state.
/// INV-9: All timestamps parsed as UTC.
class SupabaseHeartbeatQueryService implements HeartbeatQueryService {
  final SupabaseClient _client;
  final HeartbeatClassifier _classifier;

  SupabaseHeartbeatQueryService(
    this._client, [
    this._classifier = const HeartbeatClassifier(),
  ]);

  @override
  Future<HeartbeatMonitorView> getHeartbeatMonitor({
    required String organizationId,
  }) async {
    final rows =
        await _client.rpc(
              'get_device_heartbeat_status',
              params: {'p_organization_id': organizationId},
            )
            as List<dynamic>;

    final devices = rows.map((dynamic raw) {
      final row = raw as Map<String, dynamic>;
      final gapSeconds = (row['gap_seconds'] as num).toInt();
      final fleetActiveRatio =
          (row['fleet_active_ratio'] as num?)?.toDouble() ?? 0.0;

      final classification = _classifier.classify(gapSeconds, fleetActiveRatio);

      return DeviceHeartbeatStatus(
        assetId: row['asset_id'] as String,
        lastSeenAtUtc: DateTime.parse(row['last_seen_utc'] as String).toUtc(),
        gapSeconds: gapSeconds,
        classification: classification,
        fleetActiveRatio: fleetActiveRatio,
      );
    }).toList();

    return HeartbeatMonitorView(
      devices: devices,
      tamperCount: devices
          .where(
            (d) => d.classification == HeartbeatClassification.deviceTamper,
          )
          .length,
      networkIssueCount: devices
          .where(
            (d) => d.classification == HeartbeatClassification.networkIssue,
          )
          .length,
      normalCount: devices
          .where((d) => d.classification == HeartbeatClassification.normal)
          .length,
      unknownCount: devices
          .where((d) => d.classification == HeartbeatClassification.unknown)
          .length,
    );
  }
}
