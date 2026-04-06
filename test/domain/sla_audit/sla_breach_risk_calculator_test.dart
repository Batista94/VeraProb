import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_breach_risk_calculator.dart';

void main() {
  group('SlaBreachRiskCalculator', () {
    late SlaBreachRiskCalculator calculator;

    // Base window: 60-minute trip starting at 06:00 UTC, deadline 07:00 UTC.
    // buffer = 60 min * 0.15 = 9 min → risk window starts at 06:51 UTC.
    final windowStart = DateTime.utc(2026, 4, 1, 6, 0);
    final windowEnd = DateTime.utc(2026, 4, 1, 7, 0);

    setUp(() {
      calculator = const SlaBreachRiskCalculator();
    });

    // ── Buffer Calculation ────────────────────────────────────────────────

    group('15% Safety Buffer', () {
      test('buffer = 9 minutes for a 60-minute window', () {
        final eta = DateTime.utc(
          2026,
          4,
          1,
          6,
          45,
        ); // inside buffer, doesn't matter
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );

        expect(report.buffer.inSeconds, 60 * 60 * 0.15 ~/ 1); // 540s = 9 min
      });

      test('buffer = 1.5 minutes for a 10-minute window', () {
        final start = DateTime.utc(2026, 4, 1, 6, 0);
        final end = DateTime.utc(2026, 4, 1, 6, 10);
        final report = calculator.evaluate(
          windowStartUtc: start,
          windowEndUtc: end,
          currentEtaUtc: start,
        );

        // 10 min * 0.15 = 1.5 min = 90s
        expect(report.buffer.inSeconds, 90);
      });
    });

    // ── riskPercentage Formula ────────────────────────────────────────────

    group('riskPercentage formula', () {
      // Risk window starts at 06:51 (9 min before 07:00)
      // riskPct = (currentEta - 06:51) / 9min

      test(
        'returns negative when vehicle is 2 buffers (18 min) ahead of risk window',
        () {
          // 06:51 - 18 min = 06:33
          final eta = DateTime.utc(2026, 4, 1, 6, 33);
          final report = calculator.evaluate(
            windowStartUtc: windowStart,
            windowEndUtc: windowEnd,
            currentEtaUtc: eta,
          );

          // (06:33 - 06:51) / 9min = -18min / 9min = -2.0 -> -20000 bps
          expect(report.riskBps, equals(-20000));
          expect(report.riskLevel, SlaRiskLevel.safe);
        },
      );

      test(
        'returns 0.0 when currentEta is exactly at the buffer entry point',
        () {
          // risk window start = 07:00 - 9min = 06:51
          final eta = DateTime.utc(2026, 4, 1, 6, 51);
          final report = calculator.evaluate(
            windowStartUtc: windowStart,
            windowEndUtc: windowEnd,
            currentEtaUtc: eta,
          );

          expect(report.riskBps, equals(0));
        },
      );

      test('returns 0.5 when currentEta is halfway through the buffer', () {
        // halfway = 06:51 + 4.5min = 06:55:30
        final eta = DateTime.utc(2026, 4, 1, 6, 55, 30);
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );

        expect(report.riskBps, equals(5000));
        expect(report.riskLevel, SlaRiskLevel.moderate);
      });

      test('returns 0.85 at the critical threshold boundary', () {
        // 06:51 + (9min * 0.85) = 06:51 + 459s = 06:58:39
        const bufferSeconds = 540; // 9min
        final criticalOffset = (bufferSeconds * 0.85).round(); // 459s
        final eta = DateTime.utc(
          2026,
          4,
          1,
          6,
          51,
        ).add(Duration(seconds: criticalOffset));
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );

        expect(report.riskBps, equals(8500));
        expect(report.riskLevel, SlaRiskLevel.critical);
        expect(report.requiresPulse, isTrue);
      });

      test('returns 1.0 when currentEta exactly equals the SLA deadline', () {
        final eta = DateTime.utc(2026, 4, 1, 7, 0); // exactly windowEnd
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );

        expect(report.riskBps, equals(10000));
        expect(report.riskLevel, SlaRiskLevel.breached);
      });

      test('returns > 1.0 when currentEta is past the SLA deadline', () {
        // 5 min past deadline
        final eta = DateTime.utc(2026, 4, 1, 7, 5);
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );

        // (07:05 - 06:51) / 9min = 14min / 9min ≈ 1.556
        expect(report.riskBps, greaterThan(10000));
        expect(report.riskLevel, SlaRiskLevel.breached);
        expect(report.requiresPulse, isTrue);
      });

      test(
        'safe zone: returns negative for vehicle well ahead of schedule',
        () {
          final eta = DateTime.utc(2026, 4, 1, 6, 0); // trip start = 100% safe
          final report = calculator.evaluate(
            windowStartUtc: windowStart,
            windowEndUtc: windowEnd,
            currentEtaUtc: eta,
          );

          expect(report.riskBps, isNegative);
          expect(report.riskLevel, SlaRiskLevel.safe);
          expect(report.requiresPulse, isFalse);
        },
      );
    });

    // ── SlaRiskLevel Classification ───────────────────────────────────────

    group('SlaRiskLevel classification', () {
      SlaBreachRiskReport reportWithBps(int riskBps) {
        // Build a report with a known riskBps by back-calculating the ETA.
        // buffer = 540s. riskWindowStart = 06:51.
        // currentEta = riskWindowStart + (riskBps / 10000) * bufferSeconds
        const bufferSeconds = 540;
        final riskWindowStart = DateTime.utc(2026, 4, 1, 6, 51);
        final eta = riskWindowStart.add(
          Duration(
            milliseconds: (riskBps * bufferSeconds * 1000 / 10000).round(),
          ),
        );
        return calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
      }

      test('safe when riskBps < 0', () {
        expect(reportWithBps(-5000).riskLevel, SlaRiskLevel.safe);
      });

      test('low when riskBps is 0', () {
        expect(reportWithBps(0).riskLevel, SlaRiskLevel.low);
      });

      test('low when riskBps is 2500', () {
        expect(reportWithBps(2500).riskLevel, SlaRiskLevel.low);
      });

      test('moderate when riskBps is 5000', () {
        expect(reportWithBps(5000).riskLevel, SlaRiskLevel.moderate);
      });

      test('moderate when riskBps is 8400', () {
        expect(reportWithBps(8400).riskLevel, SlaRiskLevel.moderate);
      });

      test('critical when riskBps is 8500', () {
        expect(reportWithBps(8500).riskLevel, SlaRiskLevel.critical);
      });

      test('critical when riskBps is 9900', () {
        expect(reportWithBps(9900).riskLevel, SlaRiskLevel.critical);
      });

      test('breached when riskBps is 10000', () {
        expect(reportWithBps(10000).riskLevel, SlaRiskLevel.breached);
      });

      test('breached when riskBps is 20000', () {
        expect(reportWithBps(20000).riskLevel, SlaRiskLevel.breached);
      });
    });

    // ── requiresPulse Gate ────────────────────────────────────────────────

    group('requiresPulse', () {
      test('false when riskPercentage < 0.85', () {
        final eta = DateTime.utc(2026, 4, 1, 6, 51); // riskPct = 0.0
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
        expect(report.requiresPulse, isFalse);
      });

      test('true when riskPercentage >= 0.85 (critical zone)', () {
        final eta = DateTime.utc(2026, 4, 1, 6, 59); // near deadline
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
        expect(report.requiresPulse, isTrue);
      });

      test('true when riskPercentage > 1.0 (already breached)', () {
        final eta = DateTime.utc(2026, 4, 1, 7, 10);
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
        expect(report.requiresPulse, isTrue);
      });
    });

    // ── SlaBreachRiskReport Value Object ─────────────────────────────────

    group('SlaBreachRiskReport value object', () {
      test('Equatable: two reports with identical inputs are equal', () {
        final eta = DateTime.utc(2026, 4, 1, 6, 55);
        final r1 = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
        final r2 = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
        expect(r1, equals(r2));
        expect(r1.hashCode, equals(r2.hashCode));
      });

      test('report carries original window timestamps', () {
        final eta = DateTime.utc(2026, 4, 1, 6, 55);
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
        expect(report.windowStartUtc, windowStart);
        expect(report.windowEndUtc, windowEnd);
        expect(report.evaluatedAtUtc, eta);
      });

      test('buffer is a Duration object', () {
        final eta = DateTime.utc(2026, 4, 1, 6, 55);
        final report = calculator.evaluate(
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
          currentEtaUtc: eta,
        );
        expect(report.buffer, isA<Duration>());
        expect(report.buffer.inSeconds, 540); // 9 min
      });
    });

    // ── Edge Cases & Invariant Enforcement ───────────────────────────────

    group('edge cases', () {
      test('throws DomainException when windowStartUtc is not UTC (INV-9)', () {
        final localStart = DateTime(2026, 4, 1, 6, 0); // NOT UTC
        expect(
          () => calculator.evaluate(
            windowStartUtc: localStart,
            windowEndUtc: windowEnd,
            currentEtaUtc: DateTime.utc(2026, 4, 1, 6, 55),
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when windowEndUtc is not UTC (INV-9)', () {
        final localEnd = DateTime(2026, 4, 1, 7, 0); // NOT UTC
        expect(
          () => calculator.evaluate(
            windowStartUtc: windowStart,
            windowEndUtc: localEnd,
            currentEtaUtc: DateTime.utc(2026, 4, 1, 6, 55),
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when currentEtaUtc is not UTC (INV-9)', () {
        final localEta = DateTime(2026, 4, 1, 6, 55); // NOT UTC
        expect(
          () => calculator.evaluate(
            windowStartUtc: windowStart,
            windowEndUtc: windowEnd,
            currentEtaUtc: localEta,
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when window duration is zero', () {
        final sameTime = DateTime.utc(2026, 4, 1, 6, 0);
        expect(
          () => calculator.evaluate(
            windowStartUtc: sameTime,
            windowEndUtc: sameTime,
            currentEtaUtc: sameTime,
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when windowEnd is before windowStart', () {
        expect(
          () => calculator.evaluate(
            windowStartUtc: windowEnd, // reversed
            windowEndUtc: windowStart,
            currentEtaUtc: DateTime.utc(2026, 4, 1, 6, 55),
          ),
          throwsA(isA<DomainException>()),
        );
      });
    });
  });
}
