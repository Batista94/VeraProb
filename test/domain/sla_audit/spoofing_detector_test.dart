import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/spoofing_detector.dart';
import 'package:veraprob/domain/sla_audit/spoofing_signal.dart';

void main() {
  const detector = SpoofingDetector();

  CanonicalFact makeFact({
    required DateTime gpsTimestamp,
    double lat = -23.5505,
    double lng = -46.6333,
    int? speedCms = 0,
    double? accuracyMeters = 10.0,
    int? headingDegrees = 0,
  }) {
    return CanonicalFact.create(
      organizationId: 'org-1',
      rawPayloadId: 'raw-1',
      deviceId: 'DEV-1',
      sourceAdapter: 'TEST',
      receivedAtUtc: gpsTimestamp,
      gpsTimestamp: gpsTimestamp,
      lat: lat,
      lng: lng,
      speedCms: speedCms,
      accuracyMeters: accuracyMeters,
      headingDegrees: headingDegrees,
      integrityFlag: IngestionIntegrityFlag.ok,
    );
  }

  group('SpoofingDetector', () {
    test('legitimate movement returns zero risk', () {
      final t = DateTime.utc(2026, 3, 1, 10, 0);
      final facts = List.generate(10, (i) => makeFact(
        gpsTimestamp: t.add(Duration(seconds: i * 30)),
        lat: -23.5505 + (i * 0.001), // moving north
        lng: -46.6333,
        speedCms: 1000, // 36 km/h
        accuracyMeters: 10.0 + (i % 3), // variable accuracy
        headingDegrees: 0 + (i % 5), // variable heading
      ));

      final risk = detector.analyze(facts);

      expect(risk.score, 0.0);
      expect(risk.isSuspected(), isFalse);
    });

    test('static position while moving (speed > 0) triggers signal', () {
      final t = DateTime.utc(2026, 3, 1, 10, 0);
      final facts = List.generate(11, (i) => makeFact(
        gpsTimestamp: t.add(Duration(seconds: i * 30)),
        lat: -23.5505,
        lng: -46.6333,
        speedCms: 1389, // ~50 km/h
        accuracyMeters: 10.0 + i, // variable accuracy
        headingDegrees: 0 + i, // variable heading
      ));

      final risk = detector.analyze(facts);

      expect(risk.signals, contains(SpoofingSignal.staticPositionWhileMoving));
      expect(risk.score, 0.5);
    });

    test('zero entropy accuracy triggers signal', () {
      final t = DateTime.utc(2026, 3, 1, 10, 0);
      final facts = List.generate(10, (i) => makeFact(
        gpsTimestamp: t.add(Duration(seconds: i * 10)),
        accuracyMeters: 8.54321, 
        speedCms: 0, 
        headingDegrees: i, // variable
      ));

      final risk = detector.analyze(facts);

      expect(risk.signals, contains(SpoofingSignal.zeroEntropyAccuracy));
      expect(risk.score, 0.4);
    });

    test('perfect linear trajectory (constant heading) triggers signal', () {
      final t = DateTime.utc(2026, 3, 1, 10, 0);
      final facts = List.generate(20, (i) => makeFact(
        gpsTimestamp: t.add(Duration(seconds: i * 10)),
        headingDegrees: 45,
        accuracyMeters: 10.0 + i, // variable
        speedCms: 0,
      ));

      final risk = detector.analyze(facts);

      expect(risk.signals, contains(SpoofingSignal.perfectLinearTrajectory));
      expect(risk.score, 0.3);
    });

    test('multiple signals combine to exceed threshold', () {
      final t = DateTime.utc(2026, 3, 1, 10, 0);
      final facts = List.generate(20, (i) => makeFact(
        gpsTimestamp: t.add(Duration(seconds: i * 20)),
        lat: -23.5505, // static
        lng: -46.6333, // static
        speedCms: 1500, // moving
        accuracyMeters: 10.0, // zero entropy
        headingDegrees: 90, // perfect linear
      ));

      final risk = detector.analyze(facts);

      expect(risk.isSuspected(), isTrue);
      expect(risk.score, 1.0); // 0.5 + 0.4 + 0.3 = 1.2 -> clamped to 1.0
      expect(risk.signals, hasLength(3));
    });

    test('insufficient data returns zero risk', () {
      final facts = [makeFact(gpsTimestamp: DateTime.now().toUtc())];
      final risk = detector.analyze(facts);
      expect(risk.score, 0.0);
    });
  });
}
