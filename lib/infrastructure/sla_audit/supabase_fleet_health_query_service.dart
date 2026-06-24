import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/domain/sla_audit/hardware_status.dart';

/// Supabase implementation of [FleetHealthQueryService].
///
/// Calls the `get_fleet_health_status` SECURITY DEFINER RPC, which gates
/// on the JWT `app_metadata.org_id` and returns 0 rows on mismatch (INV-26).
///
/// INV-1:  organization_id always passed as an explicit parameter.
/// INV-6:  All timestamps parsed as UTC.
/// INV-7:  No `dynamic` in mapped types — strict deserialization.
class SupabaseFleetHealthQueryService implements FleetHealthQueryService {
  final SupabaseClient _client;

  SupabaseFleetHealthQueryService(this._client);

  @override
  Future<FleetHealthView> getFleetHealth({
    required String organizationId,
    int delayedSec = 900,
    int offlineSec = 3600,
  }) async {
    final rows =
        await _client.rpc(
              'get_fleet_health_status',
              params: {
                'p_organization_id': organizationId,
                'p_delayed_sec': delayedSec,
                'p_offline_sec': offlineSec,
              },
            )
            as List<dynamic>;

    var healthyCount = 0;
    var delayedCount = 0;
    var offlineCount = 0;
    var neverSeenCount = 0;
    var fleetActiveRatioBps = 0;

    final vehicles = <VehicleHealthEntry>[];

    for (final dynamic raw in rows) {
      final row = raw as Map<String, dynamic>;

      final status = HardwareStatus.fromRpcValue(
        row['hardware_status'] as String,
      );

      final statusView = switch (status) {
        HardwareStatus.healthy => HardwareStatusView.healthy,
        HardwareStatus.delayed => HardwareStatusView.delayed,
        HardwareStatus.offline => HardwareStatusView.offline,
        HardwareStatus.neverSeen => HardwareStatusView.neverSeen,
      };

      switch (status) {
        case HardwareStatus.healthy:
          healthyCount++;
        case HardwareStatus.delayed:
          delayedCount++;
        case HardwareStatus.offline:
          offlineCount++;
        case HardwareStatus.neverSeen:
          neverSeenCount++;
      }

      // Fleet active ratio is the same for all rows (CROSS JOIN in RPC).
      if (vehicles.isEmpty && row['fleet_active_ratio'] != null) {
        fleetActiveRatioBps = ((row['fleet_active_ratio'] as num) * 10000)
            .round();
      }

      final lastPingRaw = row['last_ping_utc'] as String?;

      vehicles.add(
        VehicleHealthEntry(
          vehicleId: row['vehicle_id'] as String?,
          plate: row['plate'] as String?,
          model: row['model'] as String?,
          deviceId: row['device_id'] as String?,
          lastPingUtc: lastPingRaw != null
              ? DateTime.parse(lastPingRaw).toUtc()
              : null,
          gapSeconds: (row['gap_seconds'] as num).toInt(),
          hardwareStatus: statusView,
          integrityScoreBps: (row['integrity_score_bps'] as num).toInt(),
          anomalyCount24h: (row['anomaly_count_24h'] as num).toInt(),
        ),
      );
    }

    return FleetHealthView(
      vehicles: vehicles,
      healthyCount: healthyCount,
      delayedCount: delayedCount,
      offlineCount: offlineCount,
      neverSeenCount: neverSeenCount,
      fleetActiveRatioBps: fleetActiveRatioBps,
    );
  }
}
