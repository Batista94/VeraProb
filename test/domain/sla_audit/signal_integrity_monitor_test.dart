import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/signal_integrity_monitor.dart';

void main() {
  group('SignalIntegrityMonitor', () {
    late SignalIntegrityMonitor monitor;

    setUp(() {
      monitor = const SignalIntegrityMonitor();
    });

    // ── 120s Rule ────────────────────────────────────────────────────────

    group('120s Data Silence Rule', () {
      test('no gaps when pings are ≤ 120s apart', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 1, 0), // 60s gap
          DateTime.utc(2026, 3, 1, 6, 2, 0), // 60s gap
          DateTime.utc(2026, 3, 1, 6, 3, 0), // 60s gap
        ];

        final report = monitor.analyze(timestamps);

        expect(report.gaps, isEmpty);
        expect(report.integrityScore, 100);
      });

      test('no gap flagged at exactly 120s', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 2, 0), // 120s — boundary, no flag
        ];

        final report = monitor.analyze(timestamps);

        expect(report.gaps, isEmpty);
        expect(report.integrityScore, 100);
      });

      test('gap flagged at 121s (strictly > 120s)', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 2, 1), // 121s — flag
        ];

        final report = monitor.analyze(timestamps);

        expect(report.gaps, hasLength(1));
        expect(report.gaps.first.durationSeconds, 121);
        expect(report.gaps.first.startedAtUtc, timestamps[0]);
        expect(report.gaps.first.endedAtUtc, timestamps[1]);
      });

      test('multiple gaps in a stream are detected independently', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 5, 0), // 300s gap
          DateTime.utc(2026, 3, 1, 6, 6, 0), // 60s — OK
          DateTime.utc(2026, 3, 1, 6, 10, 0), // 240s gap
          DateTime.utc(2026, 3, 1, 6, 11, 0), // 60s — OK
        ];

        final report = monitor.analyze(timestamps);

        expect(report.gaps, hasLength(2));
        expect(report.gaps[0].durationSeconds, 300);
        expect(report.gaps[1].durationSeconds, 240);
      });

      test('single timestamp produces empty report with score 100', () {
        final timestamps = [DateTime.utc(2026, 3, 1, 6, 0, 0)];

        final report = monitor.analyze(timestamps);

        expect(report.gaps, isEmpty);
        expect(report.integrityScore, 100);
      });

      test('empty timestamp list produces score 0 (no data)', () {
        final report = monitor.analyze([]);

        expect(report.gaps, isEmpty);
        expect(report.integrityScore, 0);
      });
    });

    // ── Integrity Score (0–100) ──────────────────────────────────────────

    group('Integrity Score calculation', () {
      test('100% when all gaps ≤ 120s', () {
        final timestamps = List.generate(
          61,
          (i) =>
              DateTime.utc(2026, 3, 1, 6, 0, 0).add(Duration(seconds: i * 60)),
        ); // 60 × 60s intervals = 60 min, all ≤ 120s

        final report = monitor.analyze(timestamps);

        expect(report.integrityScore, 100);
      });

      test('score degrades proportionally to silent time fraction', () {
        // Total span = 600s (10 min)
        // One 300s gap in the middle
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 1, 0), // 60s
          DateTime.utc(2026, 3, 1, 6, 6, 0), // 300s gap
          DateTime.utc(2026, 3, 1, 6, 9, 0), // 180s gap (> 120s)
          DateTime.utc(2026, 3, 1, 6, 10, 0), // 60s
        ];

        final report = monitor.analyze(timestamps);

        // Total span = 600s. Silent time = 300 + 180 = 480s.
        // Score = max(0, 100 - (480 / 600 * 100)) = max(0, 20) = 20
        expect(report.integrityScore, 20);
      });

      test('score floors at 0 when entire stream is one giant gap', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 7, 0, 0), // 3600s gap — entire stream
        ];

        final report = monitor.analyze(timestamps);

        // All of the span is silent → 0
        expect(report.integrityScore, 0);
      });

      test('score caps at 100', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 0, 30),
          DateTime.utc(2026, 3, 1, 6, 1, 0),
        ];

        final report = monitor.analyze(timestamps);

        expect(report.integrityScore, 100);
      });
    });

    // ── DataSilenceGap value object ─────────────────────────────────────

    group('DataSilenceGap', () {
      test('severity is CRITICAL when gap > 600s', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 11, 0), // 660s
        ];

        final report = monitor.analyze(timestamps);

        expect(report.gaps.first.severity, GapSeverity.critical);
      });

      test('severity is WARNING when 120s < gap ≤ 600s', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 5, 0), // 300s
        ];

        final report = monitor.analyze(timestamps);

        expect(report.gaps.first.severity, GapSeverity.warning);
      });
    });

    // ── Edge cases ──────────────────────────────────────────────────────

    group('Edge cases', () {
      test('unsorted timestamps are sorted before analysis', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 5, 0),
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 10, 0),
        ];

        final report = monitor.analyze(timestamps);

        // Gap: 300s (6:00 → 6:05) + 300s (6:05 → 6:10)
        expect(report.gaps, hasLength(2));
        expect(report.gaps[0].durationSeconds, 300);
        expect(report.gaps[1].durationSeconds, 300);
      });

      test('duplicate timestamps are tolerated (0s gap)', () {
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 1, 0),
        ];

        final report = monitor.analyze(timestamps);

        expect(report.gaps, isEmpty);
        expect(report.integrityScore, 100);
      });
    });

    // ── Integration with WS-1 Double Confirmation ──────────────────────

    group('WS-1 Integration: Double Confirmation Gate', () {
      test('requiresDoubleConfirmation is true when score < 70', () {
        // Create a stream where ~40% is silent → score ~60
        final timestamps = [
          DateTime.utc(2026, 3, 1, 6, 0, 0),
          DateTime.utc(2026, 3, 1, 6, 1, 0), // 60s OK
          DateTime.utc(2026, 3, 1, 6, 5, 0), // 240s gap
          DateTime.utc(2026, 3, 1, 6, 6, 0), // 60s OK
          DateTime.utc(2026, 3, 1, 6, 10, 0), // 240s gap
        ];

        final report = monitor.analyze(timestamps);

        expect(report.requiresDoubleConfirmation, isTrue);
        expect(report.integrityScore, lessThan(70));
      });

      test('requiresDoubleConfirmation is false when score >= 70', () {
        // Create a stream with mostly clean signals
        final timestamps = List.generate(
          30,
          (i) =>
              DateTime.utc(2026, 3, 1, 6, 0, 0).add(Duration(seconds: i * 60)),
        );
        // Add one small gap (150s at the end)
        timestamps.add(timestamps.last.add(const Duration(seconds: 150)));

        final report = monitor.analyze(timestamps);

        expect(report.requiresDoubleConfirmation, isFalse);
        expect(report.integrityScore, greaterThanOrEqualTo(70));
      });
    });
  });
}
