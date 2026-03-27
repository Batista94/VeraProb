import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'vehicle_marker.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/trip_status_view.dart';
import 'package:veraprob/application/projections/providers/fleet_attention_projection_provider.dart';
import 'package:veraprob/application/projections/models/attention_state.dart';

/// A wrapper around [MarkerLayer] that animates vehicle positions.
///
/// It maintains a local state of all vehicles and smoothly interpolates
/// their LatLng coordinates when new [VehicleOperationalState] data arrives.
///
/// Uses a single shared AnimationController for all markers to minimize
/// resource usage in stress scenarios (200+ vehicles).
class AnimatedFleetMarkerLayer extends StatefulWidget {
  final List<VehicleOperationalState> states;
  final List<dynamic> trips;
  final FleetAttentionProjection? attentionProjection;
  final String? selectedId;
  final bool showLabels;
  final void Function(String) onMarkerTap;

  const AnimatedFleetMarkerLayer({
    super.key,
    required this.states,
    required this.trips,
    this.attentionProjection,
    this.selectedId,
    this.showLabels = true,
    required this.onMarkerTap,
  });

  @override
  State<AnimatedFleetMarkerLayer> createState() =>
      _AnimatedFleetMarkerLayerState();
}

class _AnimatedFleetMarkerLayerState extends State<AnimatedFleetMarkerLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Map of vehicleId -> (oldPoint, newPoint, currentPoint)
  final Map<String, _VehicleAnimState> _animStates = {};

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addListener(() {
          setState(() {
            final t = Curves.easeInOutCubic.transform(_controller.value);
            for (final state in _animStates.values) {
              final lat =
                  state.oldPoint.latitude +
                  (state.newPoint.latitude - state.oldPoint.latitude) * t;
              final lng =
                  state.oldPoint.longitude +
                  (state.newPoint.longitude - state.oldPoint.longitude) * t;
              state.currentPoint = LatLng(lat, lng);
            }
          });
        });

    _initializeStates();
  }

  @override
  void didUpdateWidget(AnimatedFleetMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool needsAnimation = false;

    for (final newState in widget.states) {
      final existingState = _animStates[newState.vehicleId];
      final newPoint = LatLng(newState.latitude, newState.longitude);

      if (existingState == null) {
        // New vehicle, no animation needed initially
        _animStates[newState.vehicleId] = _VehicleAnimState(
          oldPoint: newPoint,
          newPoint: newPoint,
          currentPoint: newPoint,
        );
      } else if (existingState.newPoint != newPoint) {
        // Vehicle moved — start interpolation from current visual position
        // to new target. This prevents the teleport flash on controller reset.
        existingState.oldPoint = existingState.currentPoint;
        existingState.newPoint = newPoint;
        needsAnimation = true;
      }
    }

    // Remove stale vehicles
    final currentIds = widget.states.map((s) => s.vehicleId).toSet();
    _animStates.removeWhere((id, _) => !currentIds.contains(id));

    if (needsAnimation) {
      // Snapshot all non-moving markers at their current visual position
      // so they don't jump when the controller resets to 0.0
      for (final entry in _animStates.entries) {
        final state = entry.value;
        if (state.oldPoint == state.newPoint) {
          // This marker didn't move — freeze it at current position
          state.oldPoint = state.currentPoint;
          state.newPoint = state.currentPoint;
        }
      }
      _controller.forward(from: 0.0);
    }
  }

  void _initializeStates() {
    for (final state in widget.states) {
      final point = LatLng(state.latitude, state.longitude);
      _animStates[state.vehicleId] = _VehicleAnimState(
        oldPoint: point,
        newPoint: point,
        currentPoint: point,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filter out invalid or zero coordinates that shouldn't be rendered on the map
    final validStates = widget.states.where(
      (s) => s.latitude != 0.0 && s.longitude != 0.0,
    );

    final markers = validStates.map((state) {
      final animState = _animStates[state.vehicleId];
      final point =
          animState?.currentPoint ?? LatLng(state.latitude, state.longitude);

      final trip = widget.trips
          .cast<dynamic>()
          .where((t) => t.id == state.tripId)
          .firstOrNull;

      final status = trip?.status != null 
          ? TripStatusView.values.byName(trip.status.name)
          : _DefaultStatusHelper().status;
      final isSelected = state.tripId == widget.selectedId;
      final attention = widget.attentionProjection?.getContextFor(
        state.vehicleId,
      );

      return Marker(
        point: point,
        width: 48,
        height: 48,
        child: VehicleMarkerWidget(
          status: status,
          routeLabel: state.routeName ?? '?',
          motionState: state.motionState,
          confidence: state.confidence,
          heading: state.heading,
          isSelected: isSelected,
          showLabel: widget.showLabels,
          opacityMultiplier: attention?.opacityMultiplier ?? 1.0,
          isPulsing: attention?.isPulsing ?? false,
          attentionState: attention?.attentionState ?? AttentionState.normal,
          onTap: () => widget.onMarkerTap(state.tripId),
        ),
      );
    }).toList();

    return MarkerLayer(markers: markers);
  }
}

class _VehicleAnimState {
  LatLng oldPoint;
  LatLng newPoint;
  LatLng currentPoint;

  _VehicleAnimState({
    required this.oldPoint,
    required this.newPoint,
    required this.currentPoint,
  });
}

class _DefaultStatusHelper {
  TripStatusView get status => TripStatusView.scheduled;
}
