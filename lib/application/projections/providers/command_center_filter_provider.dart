import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FleetStatusFilter {
  all,
  active,
  onTime,
  delayed,
  alerts,
  atStop,
  kinematicAnomaly,
}

class CommandCenterFilterState {
  final FleetStatusFilter selectedFleetStatusFilter;
  final int? selectedSeverityFilter;
  final String? followVehicleId;

  const CommandCenterFilterState({
    this.selectedFleetStatusFilter = FleetStatusFilter.all,
    this.selectedSeverityFilter,
    this.followVehicleId,
  });

  CommandCenterFilterState copyWith({
    FleetStatusFilter? selectedFleetStatusFilter,
    int? selectedSeverityFilter,
    String? followVehicleId,
    bool clearSeverity = false,
    bool clearFollow = false,
  }) {
    return CommandCenterFilterState(
      selectedFleetStatusFilter:
          selectedFleetStatusFilter ?? this.selectedFleetStatusFilter,
      selectedSeverityFilter: clearSeverity
          ? null
          : (selectedSeverityFilter ?? this.selectedSeverityFilter),
      followVehicleId: clearFollow
          ? null
          : (followVehicleId ?? this.followVehicleId),
    );
  }
}

class CommandCenterFilterNotifier
    extends StateNotifier<CommandCenterFilterState> {
  CommandCenterFilterNotifier() : super(const CommandCenterFilterState());

  void setStatusFilter(FleetStatusFilter filter) {
    if (state.selectedFleetStatusFilter == filter) {
      state = state.copyWith(selectedFleetStatusFilter: FleetStatusFilter.all);
    } else {
      state = state.copyWith(selectedFleetStatusFilter: filter);
    }
  }

  void setSeverityFilter(int? severity) {
    if (severity == null || (state.selectedSeverityFilter == severity)) {
      state = state.copyWith(clearSeverity: true);
    } else {
      state = state.copyWith(selectedSeverityFilter: severity);
    }
  }

  void setFollowVehicleId(String? vehicleId) {
    state = state.copyWith(
      followVehicleId: vehicleId,
      clearFollow: vehicleId == null,
    );
  }
}

final commandCenterFilterProvider =
    StateNotifierProvider<
      CommandCenterFilterNotifier,
      CommandCenterFilterState
    >((ref) {
      return CommandCenterFilterNotifier();
    });
