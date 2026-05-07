import 'package:flutter/material.dart';
import 'package:veraprob/application/super_admin/tenant_technical_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Animated pulse indicator that communicates subsystem health status.
///
/// Displays a colored dot with a pulsing animation, a label, and an
/// optional subtitle. The pulse intensity varies by [PulseStatus]:
/// - [PulseStatus.healthy] → subtle pulse (scale 0.95–1.0)
/// - [PulseStatus.warning] → moderate pulse (scale 0.90–1.0)
/// - [PulseStatus.critical] → intense pulse (scale 0.85–1.0)
///
/// **INV-11:** Uses [AnimationController] with proper [dispose].
/// **INV-22:** Resides in `lib/features/super_admin/presentation/widgets/`.
///
/// **Validates: Requirements 2.1, 2.2, 2.3, 2.5, 10.2, 11.1**
class PulseIndicator extends StatefulWidget {
  final String label;
  final PulseStatus status;
  final String? subtitle;

  const PulseIndicator({
    super.key,
    required this.label,
    required this.status,
    this.subtitle,
  });

  @override
  State<PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<PulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationForStatus(widget.status),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _controller.duration = _durationForStatus(widget.status);
      _controller
        ..reset()
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Faster animation for more critical statuses to convey urgency.
  Duration _durationForStatus(PulseStatus status) {
    return switch (status) {
      PulseStatus.healthy => const Duration(milliseconds: 2000),
      PulseStatus.warning => const Duration(milliseconds: 1200),
      PulseStatus.critical => const Duration(milliseconds: 700),
    };
  }

  /// Scale range varies by status — critical pulses more dramatically.
  double _minScaleForStatus(PulseStatus status) {
    return switch (status) {
      PulseStatus.healthy => 0.95,
      PulseStatus.warning => 0.90,
      PulseStatus.critical => 0.85,
    };
  }

  /// Maps [PulseStatus] to the corresponding [VeraProbColors] semantic color.
  Color _colorForStatus(PulseStatus status) {
    return switch (status) {
      PulseStatus.healthy => VeraProbColors.success,
      PulseStatus.warning => VeraProbColors.warning,
      PulseStatus.critical => VeraProbColors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForStatus(widget.status);
    final minScale = _minScaleForStatus(widget.status);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final scale = minScale + (1.0 - minScale) * _animation.value;
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: VeraProbSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: VeraProbTypography.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: VeraProbTypography.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
