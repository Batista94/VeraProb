import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/signal_integrity_view.dart';

void main() {
  group('DataSilenceGapView', () {
    test('can be constructed', () {
      final gap = DataSilenceGapView(
        startedAtUtc: DateTime.utc(2026, 3, 1, 10, 0),
        endedAtUtc: DateTime.utc(2026, 3, 1, 10, 30),
        durationSeconds: 1800,
        severity: 'critical',
      );
      expect(gap.durationSeconds, isA<int>());
      expect(gap.severity, 'critical');
    });
  });

  group('SignalIntegrityView', () {
    test('can be constructed with required fields', () {
      const view = SignalIntegrityView(
        gaps: [],
        integrityScore: 85,
        totalSilentSeconds: 900,
        totalSpanSeconds: 3600,
        requiresDoubleConfirmation: false,
      );
      expect(view.integrityScore, isA<int>());
      expect(view.integrityScore, 85);
    });

    test('integrityScore is int (0–100)', () {
      const view = SignalIntegrityView(
        gaps: [],
        integrityScore: 100,
        totalSilentSeconds: 0,
        totalSpanSeconds: 3600,
        requiresDoubleConfirmation: false,
      );
      expect(view.integrityScore, isA<int>());
      expect(view.integrityScore, lessThanOrEqualTo(100));
    });

    test('totalSilentSeconds and totalSpanSeconds are int', () {
      const view = SignalIntegrityView(
        gaps: [],
        integrityScore: 90,
        totalSilentSeconds: 360,
        totalSpanSeconds: 3600,
        requiresDoubleConfirmation: false,
      );
      expect(view.totalSilentSeconds, isA<int>());
      expect(view.totalSpanSeconds, isA<int>());
    });
  });
}
