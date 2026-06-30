import 'package:equatable/equatable.dart';

/// Read model for a single vehicle/device health entry.
///
/// Immutable VO consumed by the Ingestion Health Monitor screen.
/// [vehicleId] and [plate] are `null` for phantom devices (INV-7: strict types,
/// no `dynamic`). The UI renders phantom devices with "Placa N/D".
///
/// [integrityScoreBps] is WS-9 compatible: 0–10,000 basis points.
class VehicleHealthEntry extends Equatable {
  /// UUID of the registered vehicle, or `null` for phantom devices.
  final String? vehicleId;

  /// License plate, or `null` for phantom devices.
  final String? plate;

  /// Vehicle model, or `null` for phantom devices.
  final String? model;

  /// Hardware device identifier (e.g., 'SASCAR-0x7F3A').
  final String? deviceId;

  /// UTC timestamp of the last received telemetry ping.
  final DateTime? lastPingUtc;

  /// Elapsed seconds since [lastPingUtc]. 999999 for NEVER_SEEN.
  final int gapSeconds;

  /// Classified hardware connectivity status.
  final HardwareStatusView hardwareStatus;

  /// Signal integrity score in basis points (0–10,000).
  /// 10,000 = perfect signal, 0 = total silence. WS-9 compatible.
  final int integrityScoreBps;

  /// Number of telemetry anomalies (integrity_flag ≠ 'OK') in the last 24h.
  final int anomalyCount24h;

  const VehicleHealthEntry({
    required this.vehicleId,
    required this.plate,
    required this.model,
    required this.deviceId,
    required this.lastPingUtc,
    required this.gapSeconds,
    required this.hardwareStatus,
    required this.integrityScoreBps,
    required this.anomalyCount24h,
  });

  /// Whether this entry represents a phantom (unregistered) device.
  bool get isPhantom => vehicleId == null;

  /// Display-safe plate: returns the actual plate or 'N/D' for phantoms.
  String get displayPlate => plate ?? 'N/D';

  @override
  List<Object?> get props => [
    vehicleId,
    plate,
    model,
    deviceId,
    lastPingUtc,
    gapSeconds,
    hardwareStatus,
    integrityScoreBps,
    anomalyCount24h,
  ];
}

/// Read model: fleet-level health snapshot for the Ingestion Health Monitor.
///
/// Produced by [FleetHealthQueryService] and consumed by the presentation layer.
/// Pre-computed counts for O(1) display in KPI chips.
class FleetHealthView extends Equatable {
  /// All vehicle/device entries, sorted worst-first by the RPC.
  final List<VehicleHealthEntry> vehicles;

  /// Count of vehicles classified as [HardwareStatus.healthy].
  final int healthyCount;

  /// Count of vehicles classified as [HardwareStatus.delayed].
  final int delayedCount;

  /// Count of vehicles classified as [HardwareStatus.offline].
  final int offlineCount;

  /// Count of vehicles classified as [HardwareStatus.neverSeen].
  final int neverSeenCount;

  /// Fleet-wide ratio of actively reporting devices in basis points (0–10,000).
  /// 10,000 = 100% active. WS-9 compatible (matches [integrityScoreBps] convention).
  final int fleetActiveRatioBps;

  const FleetHealthView({
    required this.vehicles,
    required this.healthyCount,
    required this.delayedCount,
    required this.offlineCount,
    required this.neverSeenCount,
    required this.fleetActiveRatioBps,
  });

  /// Total number of tracked entries (registered + phantom).
  int get totalCount => vehicles.length;

  /// True if any device is offline, never seen, or has anomalies.
  bool get hasAlerts =>
      offlineCount > 0 ||
      neverSeenCount > 0 ||
      vehicles.any((v) => v.anomalyCount24h > 0);

  /// Count of phantom (unregistered) devices in the result set.
  int get phantomCount => vehicles.where((v) => v.isPhantom).length;

  @override
  List<Object?> get props => [
    vehicles,
    healthyCount,
    delayedCount,
    offlineCount,
    neverSeenCount,
    fleetActiveRatioBps,
  ];
}

/// View model equivalent of `HardwareStatus` to avoid domain imports in the UI (INV-13).
enum HardwareStatusView {
  healthy,
  delayed,
  offline,
  neverSeen;

  /// Semantic label for display (Portuguese).
  String get label => switch (this) {
    HardwareStatusView.healthy => 'Saudável',
    HardwareStatusView.delayed => 'Atrasado',
    HardwareStatusView.offline => 'Offline',
    HardwareStatusView.neverSeen => 'Nunca Visto',
  };
}
