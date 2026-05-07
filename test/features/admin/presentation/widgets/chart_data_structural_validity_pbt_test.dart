import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:veraprob/core/theme/app_theme.dart';

/// **Validates: Requirements 2.2**
///
/// Property 2: Chart data structural validity
///
/// For any list of 1–24 hourly data points (each with an integer hour 0–23
/// and a non-negative double value), the BarChart configuration SHALL produce
/// a BarChartData with exactly as many BarChartGroupData entries as input
/// points, each with `x` matching the input hour and a single BarChartRodData
/// with `toY` matching the input value.

/// Represents a single hourly data point for the chart.
class HourlyDataPoint {
  final int hour; // 0–23
  final double value; // non-negative

  const HourlyDataPoint({required this.hour, required this.value});

  @override
  String toString() => 'HourlyDataPoint(hour: $hour, value: $value)';
}

/// Builds BarChartData from a list of hourly data points using the same
/// construction pattern as ChartsSection in charts_section.dart.
///
/// This mirrors the production code's approach:
/// - Each data point becomes a BarChartGroupData with x = hour
/// - Each group has a single BarChartRodData with toY = value
/// - The BarTouchTooltipData uses getTooltipColor callback (fl_chart 0.70.0 API)
BarChartData buildBarChartData(List<HourlyDataPoint> dataPoints) {
  return BarChartData(
    alignment: BarChartAlignment.spaceAround,
    maxY: dataPoints.fold<double>(
      0,
      (max, dp) => dp.value > max ? dp.value : max,
    ),
    barTouchData: BarTouchData(
      enabled: false,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => VeraProbColors.surfaceElevated,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tooltipMargin: 8,
        getTooltipItem:
            (
              BarChartGroupData group,
              int groupIndex,
              BarChartRodData rod,
              int rodIndex,
            ) {
              return BarTooltipItem(
                rod.toY.round().toString(),
                const TextStyle(
                  color: VeraProbColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
      ),
    ),
    titlesData: const FlTitlesData(show: false),
    borderData: FlBorderData(show: false),
    barGroups: dataPoints
        .map(
          (dp) => BarChartGroupData(
            x: dp.hour,
            barRods: [
              BarChartRodData(toY: dp.value, color: VeraProbColors.primary),
            ],
            showingTooltipIndicators: [0],
          ),
        )
        .toList(),
    gridData: const FlGridData(show: false),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Generators ──────────────────────────────────────────────────────────

  // Generator for the number of data points: 1–24
  final dataPointCountGen = any.intInRange(1, 25); // 1..24 inclusive

  group('Feature: dependency-upgrade-phase3, '
      'Property 2: Chart data structural validity', () {
    // ── PBT using Glados ────────────────────────────────────────────────

    Glados(dataPointCountGen).test(
      'PBT: BarChartData group count matches input data point count',
      (count) {
        // Generate `count` data points with deterministic but varied values
        final random = Random(count);
        final dataPoints = List.generate(count, (i) {
          final hour = i % 24; // Ensure unique hours within 0–23
          final value = random.nextDouble() * 100;
          return HourlyDataPoint(hour: hour, value: value);
        });

        final chartData = buildBarChartData(dataPoints);

        // Property: group count matches input count
        expect(
          chartData.barGroups.length,
          equals(dataPoints.length),
          reason:
              'BarChartData must have exactly ${dataPoints.length} groups '
              'for ${dataPoints.length} input data points',
        );
      },
    );

    Glados(dataPointCountGen).test(
      'PBT: each group x matches input hour and rod toY matches input value',
      (count) {
        final random = Random(count * 7); // different seed for variety
        final dataPoints = List.generate(count, (i) {
          final hour = i % 24;
          final value = random.nextDouble() * 100;
          return HourlyDataPoint(hour: hour, value: value);
        });

        final chartData = buildBarChartData(dataPoints);

        // Property: each group's x matches the corresponding input hour
        // and each group's single rod toY matches the input value
        for (var i = 0; i < dataPoints.length; i++) {
          final group = chartData.barGroups[i];
          final dp = dataPoints[i];

          expect(
            group.x,
            equals(dp.hour),
            reason:
                'Group[$i].x must equal input hour ${dp.hour}, '
                'got ${group.x}',
          );

          // Each group must have exactly one rod
          expect(
            group.barRods.length,
            equals(1),
            reason:
                'Group[$i] must have exactly 1 BarChartRodData, '
                'got ${group.barRods.length}',
          );

          expect(
            group.barRods[0].toY,
            equals(dp.value),
            reason:
                'Group[$i].barRods[0].toY must equal input value '
                '${dp.value}, got ${group.barRods[0].toY}',
          );
        }
      },
    );

    // ── Pre-generated iteration for broader coverage ──────────────────────
    // Glados.test uses package:test's `test`, so we also pre-generate
    // diverse inputs to ensure minimum 100 iterations with varied data.

    final random = Random(42);
    final testCases = List.generate(100, (i) {
      final count = (i % 24) + 1; // 1..24
      return List.generate(count, (j) {
        final hour = j % 24;
        final value = random.nextDouble() * 500;
        return HourlyDataPoint(hour: hour, value: value);
      });
    });

    for (var i = 0; i < testCases.length; i++) {
      final dataPoints = testCases[i];
      test('case[$i]: ${dataPoints.length} data points → '
          'structural validity holds', () {
        final chartData = buildBarChartData(dataPoints);

        // Property: group count matches
        expect(chartData.barGroups.length, equals(dataPoints.length));

        // Property: each group x and rod toY match
        for (var j = 0; j < dataPoints.length; j++) {
          expect(chartData.barGroups[j].x, equals(dataPoints[j].hour));
          expect(chartData.barGroups[j].barRods.length, equals(1));
          expect(
            chartData.barGroups[j].barRods[0].toY,
            equals(dataPoints[j].value),
          );
        }
      });
    }

    // ── Edge cases ────────────────────────────────────────────────────────

    test('single data point (minimum input) produces valid chart data', () {
      final dataPoints = [const HourlyDataPoint(hour: 0, value: 0.0)];
      final chartData = buildBarChartData(dataPoints);

      expect(chartData.barGroups.length, equals(1));
      expect(chartData.barGroups[0].x, equals(0));
      expect(chartData.barGroups[0].barRods[0].toY, equals(0.0));
    });

    test('24 data points (maximum input) produces valid chart data', () {
      final dataPoints = List.generate(
        24,
        (i) => HourlyDataPoint(hour: i, value: i * 1.5),
      );
      final chartData = buildBarChartData(dataPoints);

      expect(chartData.barGroups.length, equals(24));
      for (var i = 0; i < 24; i++) {
        expect(chartData.barGroups[i].x, equals(i));
        expect(chartData.barGroups[i].barRods[0].toY, equals(i * 1.5));
      }
    });

    test('all zero values produce valid chart data', () {
      final dataPoints = List.generate(
        12,
        (i) => HourlyDataPoint(hour: i * 2, value: 0.0),
      );
      final chartData = buildBarChartData(dataPoints);

      expect(chartData.barGroups.length, equals(12));
      for (var i = 0; i < 12; i++) {
        expect(chartData.barGroups[i].x, equals(i * 2));
        expect(chartData.barGroups[i].barRods[0].toY, equals(0.0));
      }
    });

    test('large values produce valid chart data', () {
      final dataPoints = [
        const HourlyDataPoint(hour: 23, value: 999999.99),
        const HourlyDataPoint(hour: 0, value: 0.01),
      ];
      final chartData = buildBarChartData(dataPoints);

      expect(chartData.barGroups.length, equals(2));
      expect(chartData.barGroups[0].x, equals(23));
      expect(chartData.barGroups[0].barRods[0].toY, equals(999999.99));
      expect(chartData.barGroups[1].x, equals(0));
      expect(chartData.barGroups[1].barRods[0].toY, equals(0.01));
    });
  });
}
