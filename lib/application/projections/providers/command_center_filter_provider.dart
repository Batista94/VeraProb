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
  final String? followVehicleId;

  const CommandCenterFilterState({
    this.selectedFleetStatusFilter = FleetStatusFilter.all,
    this.followVehicleId,
  });

  CommandCenterFilterState copyWith({
    FleetStatusFilter? selectedFleetStatusFilter,
    String? followVehicleId,
    bool clearFollow = false,
  }) {
    return CommandCenterFilterState(
      selectedFleetStatusFilter:
          selectedFleetStatusFilter ?? this.selectedFleetStatusFilter,
      followVehicleId: clearFollow
          ? null
          : (followVehicleId ?? this.followVehicleId),
    );
  }

  @override
  List<Object?> get props => [selectedFleetStatusFilter, followVehicleId];
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
