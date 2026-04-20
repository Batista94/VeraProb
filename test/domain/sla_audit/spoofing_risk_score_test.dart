import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/spoofing_risk_score.dart';
import 'package:veraprob/domain/sla_audit/spoofing_signal.dart';

void main() {
  group('SpoofingRiskScore — construction', () {
    test('zero() factory returns score 0 with no signals', () {
      final score = SpoofingRiskScore.zero();
      expect(score.scoreBps, 0);
      expect(score.signals, isEmpty);
    });

    test('creates score with signals', () {
      const score = SpoofingRiskScore(
        scoreBps: 7500,
        signals: [
          SpoofingSignal.staticPositionWhileMoving,
          SpoofingSignal.zeroEntropyAccuracy,
        ],
      );
      expect(score.scoreBps, 7500);
      expect(score.signals, hasLength(2));
    });
  });

  group('SpoofingRiskScore.isSuspected', () {
    test('returns false below default threshold (7000 bps)', () {
      const score = SpoofingRiskScore(scoreBps: 6999, signals: []);
      expect(score.isSuspected(), isFalse);
    });

    test('returns true at exactly default threshold (7000 bps)', () {
      const score = SpoofingRiskScore(scoreBps: 7000, signals: []);
      expect(score.isSuspected(), isTrue);
    });

    test('returns true above default threshold', () {
      const score = SpoofingRiskScore(scoreBps: 9000, signals: []);
      expect(score.isSuspected(), isTrue);
    });

    test('defaultThresholdBps is 7000', () {
      expect(SpoofingRiskScore.defaultThresholdBps, 7000);
    });

    test('respects custom threshold parameter', () {
      const score = SpoofingRiskScore(scoreBps: 5000, signals: []);
      expect(score.isSuspected(thresholdBps: 4000), isTrue);
      expect(score.isSuspected(thresholdBps: 6000), isFalse);
    });

    test('10000 bps (100%) is always suspected', () {
      const score = SpoofingRiskScore(scoreBps: 10000, signals: []);
      expect(score.isSuspected(), isTrue);
    });
  });

  group('SpoofingRiskScore.toJson / fromJson', () {
    test('roundtrip preserves scoreBps and signals', () {
      const original = SpoofingRiskScore(
        scoreBps: 8500,
        signals: [
          SpoofingSignal.routeReplayDetected,
          SpoofingSignal.impossibleAcceleration,
        ],
      );

      final json = original.toJson();
      final restored = SpoofingRiskScore.fromJson(json);

      expect(restored.scoreBps, original.scoreBps);
      expect(restored.signals, containsAll(original.signals));
    });

    test('fromJson with int score_bps parses correctly', () {
      final json = {
        'score_bps': 7500,
        'signals': ['staticPositionWhileMoving'],
      };
      final score = SpoofingRiskScore.fromJson(json);
      expect(score.scoreBps, 7500);
      expect(score.signals, [SpoofingSignal.staticPositionWhileMoving]);
    });

    test('fromJson with double score (legacy) converts to bps', () {
      // Legacy format: score as double 0.0–1.0, multiplied by 10000
      final json = {
        'score': 0.75, // 75% → 7500 bps
        'signals': <dynamic>[],
      };
      final score = SpoofingRiskScore.fromJson(json);
      expect(score.scoreBps, 7500);
    });

    test('fromJson with null score_bps defaults to 0', () {
      final json = {'signals': <dynamic>[]};
      final score = SpoofingRiskScore.fromJson(json);
      expect(score.scoreBps, 0);
    });

    test('fromJson with empty signals produces empty list', () {
      final json = {'score_bps': 1000, 'signals': <dynamic>[]};
      final score = SpoofingRiskScore.fromJson(json);
      expect(score.signals, isEmpty);
    });

    test('toJson emits score_bps key (not score)', () {
      final score = SpoofingRiskScore.zero();
      final json = score.toJson();
      expect(json.containsKey('score_bps'), isTrue);
      expect(json.containsKey('score'), isFalse);
    });
  });

  group('SpoofingRiskScore — equality', () {
    test('two identical scores are equal', () {
      const s1 = SpoofingRiskScore(
        scoreBps: 5000,
        signals: [SpoofingSignal.perfectLinearTrajectory],
      );
      const s2 = SpoofingRiskScore(
        scoreBps: 5000,
        signals: [SpoofingSignal.perfectLinearTrajectory],
      );
      expect(s1, equals(s2));
    });

    test('scores with different scoreBps are not equal', () {
      const s1 = SpoofingRiskScore(scoreBps: 5000, signals: []);
      const s2 = SpoofingRiskScore(scoreBps: 6000, signals: []);
      expect(s1, isNot(equals(s2)));
    });
  });
}
