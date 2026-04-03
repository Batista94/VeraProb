import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/heartbeat_classification.dart';
import 'package:veraprob/domain/sla_audit/heartbeat_classifier.dart';

void main() {
  const classifier = HeartbeatClassifier();

  group('HeartbeatClassifier.classify', () {
    group('normal — gap within threshold', () {
      test('gap = 0 seconds → normal', () {
        expect(classifier.classify(0, 10000), HeartbeatClassification.normal);
      });

      test('gap = 90 seconds (boundary) → normal', () {
        expect(classifier.classify(90, 0), HeartbeatClassification.normal);
      });

      test('gap = 89 seconds → normal regardless of fleet ratio', () {
        expect(classifier.classify(89, 1000), HeartbeatClassification.normal);
      });
    });

    group('deviceTamper — gap > 90s, most fleet still reporting', () {
      test('gap = 91s, ratio = 0.9 → deviceTamper', () {
        expect(
          classifier.classify(91, 9000),
          HeartbeatClassification.deviceTamper,
        );
      });

      test('gap = 91s, ratio = 0.8 (boundary) → deviceTamper', () {
        expect(
          classifier.classify(91, 8000),
          HeartbeatClassification.deviceTamper,
        );
      });

      test('gap = 300s, ratio = 1.0 → deviceTamper', () {
        expect(
          classifier.classify(300, 10000),
          HeartbeatClassification.deviceTamper,
        );
      });
    });

    group('networkIssue — gap > 90s, most fleet also offline', () {
      test('gap = 91s, ratio = 0.1 → networkIssue', () {
        expect(
          classifier.classify(91, 1000),
          HeartbeatClassification.networkIssue,
        );
      });

      test('gap = 91s, ratio = 0.3 (boundary) → networkIssue', () {
        expect(
          classifier.classify(91, 3000),
          HeartbeatClassification.networkIssue,
        );
      });

      test('gap = 600s, ratio = 0.0 → networkIssue', () {
        expect(
          classifier.classify(600, 0),
          HeartbeatClassification.networkIssue,
        );
      });
    });

    group('unknown — gap > 90s, ambiguous fleet ratio', () {
      test('gap = 91s, ratio = 0.5 → unknown', () {
        expect(classifier.classify(91, 5000), HeartbeatClassification.unknown);
      });

      test(
        'gap = 91s, ratio = 0.31 (just above network threshold) → unknown',
        () {
          expect(
            classifier.classify(91, 3100),
            HeartbeatClassification.unknown,
          );
        },
      );

      test(
        'gap = 91s, ratio = 0.79 (just below tamper threshold) → unknown',
        () {
          expect(
            classifier.classify(91, 7900),
            HeartbeatClassification.unknown,
          );
        },
      );
    });
  });

  group('DeviceHeartbeatStatus', () {
    test('creates value object with all fields', () {
      final status = DeviceHeartbeatStatus(
        assetId: 'asset-1',
        lastSeenAtUtc: DateTime.utc(2026, 1, 1, 12, 0, 0),
        gapSeconds: 120,
        classification: HeartbeatClassification.deviceTamper,
        fleetActiveBps: 9000,
      );

      expect(status.assetId, 'asset-1');
      expect(status.gapSeconds, 120);
      expect(status.classification, HeartbeatClassification.deviceTamper);
      expect(status.fleetActiveBps, equals(9000));
    });

    test('equality is structural', () {
      final t = DateTime.utc(2026, 1, 1);
      final a = DeviceHeartbeatStatus(
        assetId: 'x',
        lastSeenAtUtc: t,
        gapSeconds: 10,
        classification: HeartbeatClassification.normal,
        fleetActiveBps: 9500,
      );

      final b = DeviceHeartbeatStatus(
        assetId: 'x',
        lastSeenAtUtc: t,
        gapSeconds: 10,
        classification: HeartbeatClassification.normal,
        fleetActiveBps: 9500,
      );

      expect(a, equals(b));
    });
  });
}
