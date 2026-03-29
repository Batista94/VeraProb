import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/projections/providers/command_center_filter_provider.dart';

void main() {
  group('CommandCenterFilterProvider Coverage', () {
    test('initial state', () {
      final container = ProviderContainer();
      final state = container.read(commandCenterFilterProvider);

      expect(state.selectedFleetStatusFilter, FleetStatusFilter.all);
      expect(state.selectedSeverityFilter, isNull);
      expect(state.followVehicleId, isNull);
    });

    test('setStatusFilter toggles or sets', () {
      final container = ProviderContainer();
      final notifier = container.read(commandCenterFilterProvider.notifier);

      notifier.setStatusFilter(FleetStatusFilter.active);
      expect(
        container.read(commandCenterFilterProvider).selectedFleetStatusFilter,
        FleetStatusFilter.active,
      );

      // Toggle off -> all
      notifier.setStatusFilter(FleetStatusFilter.active);
      expect(
        container.read(commandCenterFilterProvider).selectedFleetStatusFilter,
        FleetStatusFilter.all,
      );

      // Change to another
      notifier.setStatusFilter(FleetStatusFilter.delayed);
      expect(
        container.read(commandCenterFilterProvider).selectedFleetStatusFilter,
        FleetStatusFilter.delayed,
      );
    });

    test('setSeverityFilter', () {
      final container = ProviderContainer();
      final notifier = container.read(commandCenterFilterProvider.notifier);

      notifier.setSeverityFilter(3);
      expect(
        container.read(commandCenterFilterProvider).selectedSeverityFilter,
        3,
      );

      notifier.setSeverityFilter(null);
      expect(
        container.read(commandCenterFilterProvider).selectedSeverityFilter,
        isNull,
      );
    });

    test('setFollowVehicleId', () {
      final container = ProviderContainer();
      final notifier = container.read(commandCenterFilterProvider.notifier);

      notifier.setFollowVehicleId('v1');
      expect(container.read(commandCenterFilterProvider).followVehicleId, 'v1');

      notifier.setFollowVehicleId(null);
      expect(
        container.read(commandCenterFilterProvider).followVehicleId,
        isNull,
      );
    });

    test('copyWith manually', () {
      const state = CommandCenterFilterState();
      final s2 = state.copyWith(selectedSeverityFilter: 5);
      expect(s2.selectedSeverityFilter, 5);

      final s3 = s2.copyWith(clearFollow: true);
      expect(s3.selectedSeverityFilter, 5);
      expect(s3.followVehicleId, isNull);
    });
  });
}
