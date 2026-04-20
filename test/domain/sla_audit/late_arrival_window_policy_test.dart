import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/late_arrival_window_policy.dart';

void main() {
  group('LateArrivalWindowPolicy', () {
    final windowEnd = DateTime.utc(2026, 3, 1, 11, 0, 0);

    test('returns true when receivedAtUtc is 24h after windowEndUtc', () {
      final received = windowEnd.add(const Duration(hours: 24));
      expect(
        LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: windowEnd,
          receivedAtUtc: received,
        ),
        isTrue,
      );
    });

    test(
      'returns true at exactly 48h after windowEndUtc (inclusive boundary)',
      () {
        final received = windowEnd.add(const Duration(hours: 48));
        expect(
          LateArrivalWindowPolicy.isWithinReprocessingWindow(
            windowEndUtc: windowEnd,
            receivedAtUtc: received,
          ),
          isTrue,
        );
      },
    );

    test('returns false at 48h + 1 second after windowEndUtc', () {
      final received = windowEnd.add(const Duration(hours: 48, seconds: 1));
      expect(
        LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: windowEnd,
          receivedAtUtc: received,
        ),
        isFalse,
      );
    });

    test('returns false when receivedAtUtc is 5 days after windowEndUtc', () {
      final received = windowEnd.add(const Duration(days: 5));
      expect(
        LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: windowEnd,
          receivedAtUtc: received,
        ),
        isFalse,
      );
    });

    test('returns true when receivedAtUtc is before windowEndUtc', () {
      final received = windowEnd.subtract(const Duration(hours: 1));
      expect(
        LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: windowEnd,
          receivedAtUtc: received,
        ),
        isTrue,
      );
    });

    test('returns true when receivedAtUtc is exactly at windowEndUtc', () {
      expect(
        LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: windowEnd,
          receivedAtUtc: windowEnd,
        ),
        isTrue,
      );
    });

    test('returns true with custom 24h window when within range', () {
      final received = windowEnd.add(const Duration(hours: 23));
      expect(
        LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: windowEnd,
          receivedAtUtc: received,
          window: const Duration(hours: 24),
        ),
        isTrue,
      );
    });

    test('returns false with custom 24h window when outside range', () {
      final received = windowEnd.add(const Duration(hours: 24, seconds: 1));
      expect(
        LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: windowEnd,
          receivedAtUtc: received,
          window: const Duration(hours: 24),
        ),
        isFalse,
      );
    });
  });
}
