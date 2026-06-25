import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/state/providers/fleet_health_providers.dart';

const _kVehicleId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

VehicleHealthEntry _entry() => VehicleHealthEntry(
  vehicleId: _kVehicleId,
  plate: 'ABC-1234',
  model: 'Volvo FH',
  deviceId: 'SASCAR-0x7F3A',
  lastPingUtc: DateTime.utc(2026, 6, 20, 12),
  gapSeconds: 90,
  hardwareStatus: HardwareStatusView.delayed,
  integrityScoreBps: 6500,
  anomalyCount24h: 0,
);

final _kView = FleetHealthView(
  vehicles: [_entry()],
  healthyCount: 0,
  delayedCount: 1,
  offlineCount: 0,
  neverSeenCount: 0,
  fleetActiveRatioBps: 6500,
);

void main() {
  group('resolvedPreselectionProvider', () {
    test('returns null when candidateId is null', () {
      final container = ProviderContainer(
        overrides: [
          fleetHealthPollingProvider.overrideWith(
            (ref) => Stream.value(_kView),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(resolvedPreselectionProvider(null)), isNull);
    });

    test('returns null when candidateId is empty', () {
      final container = ProviderContainer(
        overrides: [
          fleetHealthPollingProvider.overrideWith(
            (ref) => Stream.value(_kView),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(resolvedPreselectionProvider('')), isNull);
    });

    test('returns null when fleet data is still pending (no emission)', () {
      // StreamController that never emits — simulates loading.
      final controller = StreamController<FleetHealthView>();
      addTearDown(controller.close);

      final container = ProviderContainer(
        overrides: [
          fleetHealthPollingProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);

      // Keep the provider alive by listening.
      container.listen(fleetHealthPollingProvider, (_, _) {});

      expect(container.read(resolvedPreselectionProvider(_kVehicleId)), isNull);
    });

    test('returns candidateId when found in loaded fleet', () async {
      final container = ProviderContainer(
        overrides: [
          fleetHealthPollingProvider.overrideWith(
            (ref) => Stream.value(_kView),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Keep provider alive and wait for emission.
      container.listen(fleetHealthPollingProvider, (_, _) {});
      await container.read(fleetHealthPollingProvider.future);

      expect(
        container.read(resolvedPreselectionProvider(_kVehicleId)),
        _kVehicleId,
      );
    });

    test('returns null when candidateId is absent from loaded fleet', () async {
      final container = ProviderContainer(
        overrides: [
          fleetHealthPollingProvider.overrideWith(
            (ref) => Stream.value(_kView),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Keep provider alive and wait for emission.
      container.listen(fleetHealthPollingProvider, (_, _) {});
      await container.read(fleetHealthPollingProvider.future);

      const foreignId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
      expect(container.read(resolvedPreselectionProvider(foreignId)), isNull);
    });
  });
}
