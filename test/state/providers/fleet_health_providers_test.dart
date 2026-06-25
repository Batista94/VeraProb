import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/fleet_health_providers.dart';

void main() {
  group('selectedHealthVehicleIdProvider', () {
    test('starts unselected (null)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(selectedHealthVehicleIdProvider), isNull);
    });

    test('set stores and clears the selected id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(selectedHealthVehicleIdProvider.notifier);

      notifier.set('veh-1');
      expect(container.read(selectedHealthVehicleIdProvider), 'veh-1');

      notifier.set(null);
      expect(container.read(selectedHealthVehicleIdProvider), isNull);
    });
  });

  group('fleetHealthPollingProvider', () {
    test('emits an empty fleet view when no organization is set', () async {
      final container = ProviderContainer(
        overrides: [currentOrganizationIdProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      // Keep the autoDispose provider alive while awaiting its first emission.
      container.listen(fleetHealthPollingProvider, (_, _) {});
      final view = await container.read(fleetHealthPollingProvider.future);

      expect(view, isA<FleetHealthView>());
      expect(view.totalCount, 0);
      expect(view.hasAlerts, isFalse);
      expect(view.fleetActiveRatioBps, 0);
    });
  });
}
