import 'package:flutter/material.dart';
import 'package:veraprob/application/normalization/models/trip_status_view.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/projections/models/attention_state.dart';
import 'package:veraprob/presentation/shared/trip_status_theme.dart';

const Color _kCriticalRing = Color(0xFFFF1744);

/// A map marker representing a vehicle, colored by trip status.
///
/// Visual hierarchy (OCC Operational Standard):
/// - NORMAL: 14px dot, status color fill, white border
/// - WARNING (delay): 16px dot, amber fill, no ring, no pulse
/// - CRITICAL (emergency): 18px dot, red ring border, pulsing halo
/// - isSelected: white glow (blurRadius 12, spreadRadius 4)
class VehicleMarkerWidget extends StatelessWidget {
  final TripStatusView status;
  final String routeLabel;
  final double? heading;
  final MotionState? motionState;
  final double confidence;
  final bool isSelected;
  final bool showLabel;
  final double opacityMultiplier;
  final bool isPulsing;
  final AttentionState attentionState;
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
    this.attentionState = AttentionState.normal,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    final baseOpacity = (confidence * 0.8) + 0.2;
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
            // Vehicle dot with tiered visual hierarchy
            _buildDot(color),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(Color color) {
    // Tiered sizing based on AttentionState, not TripStatus
    final double dotSize;
    switch (attentionState) {
      case AttentionState.critical:
        dotSize = isSelected ? 22 : 18;
      case AttentionState.warning:
        dotSize = isSelected ? 20 : 16;
      case AttentionState.normal:
        dotSize = isSelected ? 18 : 14;
    }

    final isCritical = attentionState == AttentionState.critical;

    final dot = Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          // Red ring ONLY for CRITICAL, white for everything else
          color: isCritical
              ? _kCriticalRing
              : (isSelected ? Colors.white : Colors.white70),
          width: isCritical ? (isSelected ? 3.5 : 2.5) : (isSelected ? 3 : 1.5),
        ),
        boxShadow: [
          // Strong glow for selected vehicle
          if (isSelected)
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 4,
            ),
          if (isCritical && !isSelected)
            BoxShadow(
              color: _kCriticalRing.withValues(alpha: 0.4),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child:
          (motionState == MotionState.dwellingAtStop ||
              status == TripStatusView.atStop)
          ? Icon(Icons.hail, size: isSelected ? 10 : 8, color: Colors.white)
          : null,
    );

    // Pulsing ring ONLY for CRITICAL attention state
    if (isPulsing && isCritical) {
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
        final extraSpread = _animation.value * 24.0;

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(
                  alpha: 0.8 - (_animation.value * 0.8),
                ),
                blurRadius: widget.isSelected ? 20 : 16,
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
