import 'package:flutter/material.dart';

/// Lightweight 7/30-day volatility minigraph for CFO KPI cards.
/// Pure CustomPaint polyline — no axes, grid, labels, or tooltip.
/// RepaintBoundary isolates each card's repaint for 60fps under N cards.
class SparklineWidget extends StatelessWidget {
  final List<int> values;
  final Color color;
  final double height;
  final double strokeWidth;

  const SparklineWidget({
    super.key,
    required this.values,
    required this.color,
    this.height = 32,
    this.strokeWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _SparklinePainter(
            values: values,
            color: color,
            strokeWidth: strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final Color color;
  final double strokeWidth;

  const _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) {
      // Single point or empty: flat mid-line.
      final paint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    final minVal = values.reduce((a, b) => a < b ? a : b).toDouble();
    final maxVal = values.reduce((a, b) => a > b ? a : b).toDouble();
    final range = maxVal - minVal;

    double yOf(int v) {
      if (range == 0) return size.height / 2;
      return size.height - (v - minVal) / range * size.height;
    }

    double xOf(int i) => i / (n - 1) * size.width;

    // Area fill (low alpha).
    final areaPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final areaPath = Path()..moveTo(xOf(0), yOf(values[0]));
    for (var i = 1; i < n; i++) {
      areaPath.lineTo(xOf(i), yOf(values[i]));
    }
    areaPath
      ..lineTo(xOf(n - 1), size.height)
      ..lineTo(xOf(0), size.height)
      ..close();
    canvas.drawPath(areaPath, areaPaint);

    // Polyline.
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final linePath = Path()..moveTo(xOf(0), yOf(values[0]));
    for (var i = 1; i < n; i++) {
      linePath.lineTo(xOf(i), yOf(values[i]));
    }
    canvas.drawPath(linePath, strokePaint);

    // Last-point dot.
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(xOf(n - 1), yOf(values[n - 1])),
      strokeWidth + 1,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
