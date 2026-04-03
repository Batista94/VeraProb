import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// Risk Thermometer Widget — visual indicator of SLA breach proximity.
///
/// Displays:
/// 1. A vertical gradient bar (green→amber→red) with a fill marker.
/// 2. A risk level label with percentage.
/// 3. A pulsing glow animation when [report.requiresPulse] is true
///    (riskPercentage ≥ 0.85, i.e. critical or breached zone).
///
/// Links to WS-2: shows either the live predictive risk (KPI context)
/// or the historical breach severity (verdict card context).
///
/// INV-4: zero dart:html / dart:js — WASM-safe.
class RiskThermometerWidget extends StatefulWidget {
  /// The risk report to visualize.
  final SlaBreachRiskReport report;

  /// Height of the thermometer bar component.
  final double height;

  const RiskThermometerWidget({
    super.key,
    required this.report,
    this.height = 80.0,
  });

  @override
  State<RiskThermometerWidget> createState() => _RiskThermometerState();
}

class _RiskThermometerState extends State<RiskThermometerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.report.requiresPulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RiskThermometerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.report.requiresPulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.report.requiresPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: widget.report.requiresPulse
                  ? _pulseAnimation.value
                  : 1.0,
              child: child,
            );
          },
          child: SizedBox(
            width: 12,
            height: widget.height,
            child: CustomPaint(
              painter: _ThermometerBarPainter(
                fillLevel: (widget.report.riskBps / 10000).clamp(0.0, 1.0),
                riskLevel: widget.report.riskLevel,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _RiskLevelLabel(report: widget.report),
      ],
    );
  }
}

/// Vertical gradient bar with a fill level marker.
///
/// Bottom = safe (green), middle = warning (amber), top = critical (red).
/// The fill marker sits at [fillLevel] (0.0 = bottom, 1.0 = top).
class _ThermometerBarPainter extends CustomPainter {
  final double fillLevel; // 0.0–1.0 (clamped externally)
  final SlaRiskLevel riskLevel;

  const _ThermometerBarPainter({
    required this.fillLevel,
    required this.riskLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGradientBar(canvas, size);
    _drawFillMarker(canvas, size);
  }

  void _drawGradientBar(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        VeraProbColors.success,
        VeraProbColors.warning,
        VeraProbColors.error,
      ],
      stops: [0.0, 0.5, 1.0],
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, paint);
  }

  void _drawFillMarker(Canvas canvas, Size size) {
    // Marker sits at fillLevel from bottom — invert for canvas (0 = top).
    final markerY = size.height * (1.0 - fillLevel);
    final markerColor = _markerColor();
    final paint = Paint()
      ..color = markerColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, markerY), Offset(size.width, markerY), paint);
  }

  Color _markerColor() {
    switch (riskLevel) {
      case SlaRiskLevel.safe:
      case SlaRiskLevel.low:
        return VeraProbColors.success;
      case SlaRiskLevel.moderate:
        return VeraProbColors.warning;
      case SlaRiskLevel.critical:
      case SlaRiskLevel.breached:
        return VeraProbColors.error;
    }
  }

  @override
  bool shouldRepaint(_ThermometerBarPainter oldDelegate) =>
      oldDelegate.fillLevel != fillLevel || oldDelegate.riskLevel != riskLevel;
}

/// Text label showing the risk level and percentage.
class _RiskLevelLabel extends StatelessWidget {
  final SlaBreachRiskReport report;

  const _RiskLevelLabel({required this.report});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor();
    final label = _levelLabel();
    final pct = (report.riskBps ~/ 100).clamp(0, 999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          report.riskLevel == SlaRiskLevel.safe
          ? 'Confortável'
          : '$pct% do buffer',
          style: const TextStyle(
            fontSize: 9,
            color: VeraProbColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Color _levelColor() {
    switch (report.riskLevel) {
      case SlaRiskLevel.safe:
      case SlaRiskLevel.low:
        return VeraProbColors.success;
      case SlaRiskLevel.moderate:
        return VeraProbColors.warning;
      case SlaRiskLevel.critical:
      case SlaRiskLevel.breached:
        return VeraProbColors.error;
    }
  }

  String _levelLabel() {
    switch (report.riskLevel) {
      case SlaRiskLevel.safe:
        return 'SEGURO';
      case SlaRiskLevel.low:
        return 'BAIXO RISCO';
      case SlaRiskLevel.moderate:
        return 'ATENÇÃO';
      case SlaRiskLevel.critical:
        return 'CRÍTICO';
      case SlaRiskLevel.breached:
        return 'VIOLADO';
    }
  }
}
