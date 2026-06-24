/// Hardware connectivity classification for fleet ingestion health.
///
/// Maps 1:1 to the `hardware_status` TEXT returned by the
/// `get_fleet_health_status` RPC. Pure domain — zero dependencies.
///
/// - [healthy]: gap ≤ `p_delayed_sec` (default 15 min).
/// - [delayed]: gap between `p_delayed_sec` and `p_offline_sec`.
/// - [offline]: gap > `p_offline_sec` (default 1h).
/// - [neverSeen]: no telemetry data recorded for this vehicle.
enum HardwareStatus {
  healthy,
  delayed,
  offline,
  neverSeen;

  /// Parses the TEXT value returned by the RPC.
  ///
  /// Throws [ArgumentError] for unknown values (INV-7: strict types).
  static HardwareStatus fromRpcValue(String value) => switch (value) {
    'HEALTHY' => HardwareStatus.healthy,
    'DELAYED' => HardwareStatus.delayed,
    'OFFLINE' => HardwareStatus.offline,
    'NEVER_SEEN' => HardwareStatus.neverSeen,
    _ => throw ArgumentError('Unknown HardwareStatus: $value'),
  };

  /// Semantic label for display (Portuguese).
  String get label => switch (this) {
    HardwareStatus.healthy => 'Saudável',
    HardwareStatus.delayed => 'Atrasado',
    HardwareStatus.offline => 'Offline',
    HardwareStatus.neverSeen => 'Nunca Visto',
  };
}
