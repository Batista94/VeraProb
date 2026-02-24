import 'package:flutter/material.dart';
import 'package:busflow/domain/enums/trip_status.dart';
import 'package:busflow/domain/enums/motion_state.dart';

/// A map marker representing a vehicle, colored by trip status.
///
/// Renders as a directional arrow (when heading is known) or a dot,
/// with the trip's status color and a route label.
class VehicleMarkerWidget extends StatelessWidget {
  final TripStatus status;
  final String routeLabel;
  final double? heading;
  final MotionState? motionState;
  final double confidence;
  final bool isSelected;
  final bool showLabel;
  final double opacityMultiplier;
  final bool isPulsing;
  final VoidCallback? onTap;

  const VehicleMarkerWidget({
    super.key,
    required this.status,
    required this.routeLabel,
    this.heading,
    this.motionState,
    this.confidence = 1.0,
    this.isSelected = false,
    this.showLabel = true,
    this.opacityMultiplier = 1.0,
    this.isPulsing = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    // Map confidence directly to opacity (with a minimum baseline so it doesn't disappear completely)
    final baseOpacity = (confidence * 0.7) + 0.3; // 1.0 -> 1.0, 0.0 -> 0.3
    final finalOpacity = baseOpacity * opacityMultiplier;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 500),
        opacity: finalOpacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Route label
            if (showLabel)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  routeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            if (showLabel) const SizedBox(height: 2),
            // Vehicle dot
            _buildDot(color),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(Color color) {
    final dot = Container(
      width: isSelected ? 18 : 14,
      height: isSelected ? 18 : 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.white : Colors.white70,
          width: isSelected ? 3 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: isSelected ? 8 : 4,
            spreadRadius: isSelected ? 2 : 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child:
          (motionState == MotionState.dwellingAtStop ||
              status == TripStatus.atStop)
          ? Icon(Icons.hail, size: isSelected ? 10 : 8, color: Colors.white)
          : null,
    );

    if (isPulsing) {
      return _PulsingRing(color: color, isSelected: isSelected, child: dot);
    }
    return dot;
  }
}

class _PulsingRing extends StatefulWidget {
  final Widget child;
  final Color color;
  final bool isSelected;
  const _PulsingRing({
    required this.child,
    required this.color,
    required this.isSelected,
  });

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final spread = widget.isSelected ? 4.0 : 2.0;
        final extraSpread = _animation.value * 8.0;

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(
                  alpha: 0.6 - (_animation.value * 0.4),
                ),
                blurRadius: widget.isSelected ? 12 : 8,
                spreadRadius: spread + extraSpread,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
