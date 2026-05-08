import 'package:equatable/equatable.dart';
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

class CommandCenterFilterState extends Equatable {
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

  @override
  List<Object?> get props => [
    selectedFleetStatusFilter,
    selectedSeverityFilter,
    followVehicleId,
  ];
}

class CommandCenterFilterNotifier extends Notifier<CommandCenterFilterState> {
  @override
  CommandCenterFilterState build() {
    return const CommandCenterFilterState();
  }

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
    NotifierProvider<CommandCenterFilterNotifier, CommandCenterFilterState>(
      CommandCenterFilterNotifier.new,
    );
