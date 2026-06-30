import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';

void main() {
  VehicleHealthEntry entry({
    String? vehicleId = 'veh-1',
    String? plate = 'ABC-1234',
    String? deviceId = 'SASCAR-1',
    HardwareStatusView status = HardwareStatusView.healthy,
    int anomalyCount24h = 0,
  }) {
    return VehicleHealthEntry(
      vehicleId: vehicleId,
      plate: plate,
      model: 'Atego',
      deviceId: deviceId,
      lastPingUtc: DateTime.utc(2026, 3, 1, 12),
      gapSeconds: 60,
      hardwareStatus: status,
      integrityScoreBps: 9000,
      anomalyCount24h: anomalyCount24h,
    );
  }

  group('VehicleHealthEntry', () {
    test('registered vehicle is not phantom and shows its plate', () {
      final e = entry();
      expect(e.isPhantom, isFalse);
      expect(e.displayPlate, 'ABC-1234');
    });

    test('null vehicleId marks a phantom device with N/D plate', () {
      final e = entry(vehicleId: null, plate: null);
      expect(e.isPhantom, isTrue);
      expect(e.displayPlate, 'N/D');
    });
  });

  group('FleetHealthView', () {
    FleetHealthView view(List<VehicleHealthEntry> vehicles) => FleetHealthView(
      vehicles: vehicles,
      healthyCount: 0,
      delayedCount: 0,
      offlineCount: 0,
      neverSeenCount: 0,
      fleetActiveRatioBps: 10000,
    );

    test('totalCount counts all entries', () {
      expect(view([entry(), entry(vehicleId: 'veh-2')]).totalCount, 2);
    });

    test('phantomCount counts only unregistered devices', () {
      final v = view([entry(), entry(vehicleId: null, plate: null)]);
      expect(v.phantomCount, 1);
    });

    test('hasAlerts is false for a clean fleet', () {
      expect(view([entry()]).hasAlerts, isFalse);
    });

    test('hasAlerts is true when a device is offline', () {
      final v = FleetHealthView(
        vehicles: [entry(status: HardwareStatusView.offline)],
        healthyCount: 0,
        delayedCount: 0,
        offlineCount: 1,
        neverSeenCount: 0,
        fleetActiveRatioBps: 0,
      );
      expect(v.hasAlerts, isTrue);
    });

    test('hasAlerts is true when any entry has 24h anomalies', () {
      expect(view([entry(anomalyCount24h: 3)]).hasAlerts, isTrue);
    });
  });

  group('HardwareStatusView', () {
    test('every status carries a Portuguese label', () {
      expect(HardwareStatusView.healthy.label, 'Saudável');
      expect(HardwareStatusView.delayed.label, 'Atrasado');
      expect(HardwareStatusView.offline.label, 'Offline');
      expect(HardwareStatusView.neverSeen.label, 'Nunca Visto');
    });
  });
}
