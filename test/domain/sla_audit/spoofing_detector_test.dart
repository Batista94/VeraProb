// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/spoofing_detector.dart';
import 'package:veraprob/domain/sla_audit/spoofing_signal.dart';

// ---------------------------------------------------------------------------
// FORENSIC AUDIT SUITE — SpoofingDetector
// Invariants: INV-8 (Repo Isolation / Stillness), INV-18 (Zero-Trust Telemetry)
//             INV-6 (UTC), INV-12 (Physical Metric annotation)
//
// Constraints:
//   · NO any() matchers — all assertions are explicit
//   · NO dynamic loops for fact generation — hardcoded fixture arrays
//   · Real-world city coordinates for geographic tests
//   · All timestamps UTC (INV-6)
// ---------------------------------------------------------------------------

void main() {
  const detector = SpoofingDetector();

  // -------------------------------------------------------------------------
  // Fixture builder — keeps test bodies readable without dynamic loops.
  // -------------------------------------------------------------------------
  CanonicalFact fact({
    required DateTime ts,
    required double lat, // Physical Metric - Double Required
    required double lng, // Physical Metric - Double Required
    int speedCms = 0,
    double accuracyMeters = 12.5, // Physical Metric - Double Required
    int headingDegrees = 45,
  }) {
    return CanonicalFact.create(
      organizationId: 'org-forensic',
      rawPayloadId: 'raw-forensic',
      deviceId: 'DEV-FORENSIC',
      sourceAdapter: 'TEST',
      receivedAtUtc: ts,
      gpsTimestamp: ts,
      lat: lat,
      lng: lng,
      speedCms: speedCms,
      accuracyMeters: accuracyMeters,
      headingDegrees: headingDegrees,
      integrityFlag: IngestionIntegrityFlag.ok,
    );
  }

  // =========================================================================
  // GROUP 1 — INV-8 · STILLNESS DETECTION
  //
  // Zero-displacement while reporting speed is the GPS emulator signature.
  // The detector requires: window ≥ 5 min, ≥ 5 moving facts, maxDist < 2 m.
  // =========================================================================
  group('INV-8 · STILLNESS DETECTION', () {
    // STILL-01: 10 pings, exact same SP coordinates, speed 50 km/h (1389 cm/s)
    // Window: t=0..t=600s (10 min) — well above the 5-min gate.
    test(
      'STILL-01: identical coordinates + speed > 0 → staticPositionWhileMoving',
      () {
        // Terminal Tietê, São Paulo — hardcoded
        const double lat = -23.5158; // Physical Metric - Double Required
        const double lng = -46.6258; // Physical Metric - Double Required
        final t0 = DateTime.utc(2026, 4, 14, 8, 0, 0);

        final facts = [
          fact(
            ts: t0,
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 8.1,
            headingDegrees: 10,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 60)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 9.3,
            headingDegrees: 12,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 120)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 7.8,
            headingDegrees: 8,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 180)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 10.2,
            headingDegrees: 15,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 240)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 11.0,
            headingDegrees: 7,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 300)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 8.5,
            headingDegrees: 13,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 360)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 9.0,
            headingDegrees: 11,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 420)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 7.6,
            headingDegrees: 9,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 480)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 10.8,
            headingDegrees: 14,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 540)),
            lat: lat,
            lng: lng,
            speedCms: 1389,
            accuracyMeters: 8.9,
            headingDegrees: 6,
          ),
        ];

        final risk = detector.analyze(facts);

        expect(
          risk.signals,
          contains(SpoofingSignal.staticPositionWhileMoving),
          reason:
              'STILL-01: 10 identical positions with speed MUST flag staticPositionWhileMoving',
        );
        expect(
          risk.scoreBps,
          greaterThanOrEqualTo(5000),
          reason: 'STILL-01: staticPositionWhileMoving contributes 5000 bps',
        );
      },
    );

    // STILL-02: Micro-variation only at 10th decimal place (< 1 mm displacement).
    // Emulators sometimes add a tiny jitter to evade naive equality checks.
    // The haversine distance of 1e-10° × 111,319 m/° ≈ 1.1e-5 m per step;
    // total across 9 steps ≈ 0.0001 m — far below the 2 m threshold.
    test(
      'STILL-02: sub-millimetre jitter (1e-10°) is still detected as static',
      () {
        const double baseLat = -23.5158; // Physical Metric - Double Required
        const double baseLng = -46.6258; // Physical Metric - Double Required
        final t0 = DateTime.utc(2026, 4, 14, 9, 0, 0);

        final facts = [
          fact(
            ts: t0,
            lat: baseLat + 0.0000000000,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 8.1,
            headingDegrees: 10,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 60)),
            lat: baseLat + 0.0000000001,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 9.3,
            headingDegrees: 12,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 120)),
            lat: baseLat + 0.0000000002,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 7.8,
            headingDegrees: 8,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 180)),
            lat: baseLat + 0.0000000003,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 10.2,
            headingDegrees: 15,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 240)),
            lat: baseLat + 0.0000000004,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 11.0,
            headingDegrees: 7,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 300)),
            lat: baseLat + 0.0000000005,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 8.5,
            headingDegrees: 13,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 360)),
            lat: baseLat + 0.0000000006,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 9.0,
            headingDegrees: 11,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 420)),
            lat: baseLat + 0.0000000007,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 7.6,
            headingDegrees: 9,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 480)),
            lat: baseLat + 0.0000000008,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 10.8,
            headingDegrees: 14,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 540)),
            lat: baseLat + 0.0000000009,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 8.9,
            headingDegrees: 6,
          ),
        ];

        final risk = detector.analyze(facts);

        expect(
          risk.signals,
          contains(SpoofingSignal.staticPositionWhileMoving),
          reason:
              'STILL-02: sub-mm jitter must NOT fool the stillness detector',
        );
        expect(risk.scoreBps, greaterThanOrEqualTo(5000));
      },
    );
  });

  // =========================================================================
  // GROUP 2 — INV-18 · VELOCITY GUARD
  //
  // SP Terminal Tietê → RJ Rodoviária Novo Rio in 10 seconds.
  // Real haversine distance ≈ 359 km → 35,900,000 cm / 10 s = 3,590,000 cm/s.
  // Limit: 4,167 cm/s (150 km/h). Ratio: ×862 — unambiguous teleport.
  // =========================================================================
  group('INV-18 · VELOCITY GUARD', () {
    test('VEL-01: SP→RJ teleport in 10s → impossiblePositionJump (≥ 8000 bps)', () {
      final t0 = DateTime.utc(2026, 4, 14, 10, 0, 0);

      // Padding facts at SP to satisfy minimum-window requirements of other checks.
      // These 4 pings are all at Terminal Tietê — speed realistic (1000 cm/s = 36 km/h).
      const double spLat =
          -23.5158; // Physical Metric - Double Required (Terminal Tietê, SP)
      const double spLng = -46.6258; // Physical Metric - Double Required
      const double rjLat =
          -22.9108; // Physical Metric - Double Required (Rodoviária Novo Rio, RJ)
      const double rjLng = -43.1729; // Physical Metric - Double Required

      final facts = [
        fact(
          ts: t0,
          lat: spLat,
          lng: spLng,
          speedCms: 1000,
          accuracyMeters: 9.1,
          headingDegrees: 40,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 30)),
          lat: spLat - 0.0002,
          lng: spLng + 0.0001,
          speedCms: 1100,
          accuracyMeters: 8.7,
          headingDegrees: 42,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 60)),
          lat: spLat - 0.0004,
          lng: spLng + 0.0002,
          speedCms: 950,
          accuracyMeters: 10.3,
          headingDegrees: 39,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 90)),
          lat: spLat - 0.0006,
          lng: spLng + 0.0003,
          speedCms: 1050,
          accuracyMeters: 9.5,
          headingDegrees: 41,
        ),
        // TELEPORT: ping 4 → ping 5 = 10 s, ~359 km → impossible
        fact(
          ts: t0.add(const Duration(seconds: 100)),
          lat: rjLat,
          lng: rjLng,
          speedCms: 1000,
          accuracyMeters: 9.2,
          headingDegrees: 40,
        ),
      ];

      final risk = detector.analyze(facts);

      expect(
        risk.signals,
        contains(SpoofingSignal.impossiblePositionJump),
        reason: 'VEL-01: 359 km in 10 s MUST flag impossiblePositionJump',
      );
      expect(
        risk.scoreBps,
        greaterThanOrEqualTo(8000),
        reason: 'VEL-01: impossiblePositionJump weight = 8000 bps',
      );
      expect(
        risk.isSuspected(),
        isTrue,
        reason: 'VEL-01: score must exceed 7000 bps suspicion threshold',
      );
    });
  });

  // =========================================================================
  // GROUP 3 — TEMPORAL · CHRONOLOGICAL INTEGRITY
  //
  // GPS timestamps must be strictly ascending (INV-18 / INV-6).
  // A single out-of-order pair is sufficient to flag the entire window.
  // =========================================================================
  group('TEMPORAL · CHRONOLOGICAL INTEGRITY', () {
    test(
      'TEMP-01: out-of-order timestamp at index 2 → temporalAnomaly (≥ 7000 bps)',
      () {
        final t0 = DateTime.utc(2026, 4, 14, 11, 0, 0);

        // Campinas — hardcoded reference
        const double lat = -22.9056; // Physical Metric - Double Required
        const double lng = -47.0608; // Physical Metric - Double Required

        final facts = [
          // t=0    → normal
          fact(
            ts: t0,
            lat: lat + 0.000,
            lng: lng + 0.000,
            speedCms: 800,
            accuracyMeters: 10.2,
            headingDegrees: 30,
          ),
          // t=+30s → normal
          fact(
            ts: t0.add(const Duration(seconds: 30)),
            lat: lat + 0.001,
            lng: lng + 0.001,
            speedCms: 820,
            accuracyMeters: 9.8,
            headingDegrees: 32,
          ),
          // t=+20s → REVERSAL: 20 s < 30 s → temporal anomaly
          fact(
            ts: t0.add(const Duration(seconds: 20)),
            lat: lat + 0.002,
            lng: lng + 0.002,
            speedCms: 790,
            accuracyMeters: 11.1,
            headingDegrees: 29,
          ),
          // t=+60s → ascending again (anomaly already triggered)
          fact(
            ts: t0.add(const Duration(seconds: 60)),
            lat: lat + 0.003,
            lng: lng + 0.003,
            speedCms: 810,
            accuracyMeters: 10.5,
            headingDegrees: 31,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 90)),
            lat: lat + 0.004,
            lng: lng + 0.004,
            speedCms: 830,
            accuracyMeters: 9.3,
            headingDegrees: 33,
          ),
        ];

        final risk = detector.analyze(facts);

        expect(
          risk.signals,
          contains(SpoofingSignal.temporalAnomaly),
          reason: 'TEMP-01: non-ascending timestamps MUST flag temporalAnomaly',
        );
        expect(
          risk.scoreBps,
          greaterThanOrEqualTo(7000),
          reason: 'TEMP-01: temporalAnomaly weight = 7000 bps',
        );
        expect(
          risk.isSuspected(),
          isTrue,
          reason: 'TEMP-01: temporal anomaly alone exceeds suspicion threshold',
        );
      },
    );
  });

  // =========================================================================
  // GROUP 4 — FALSE POSITIVE · REAL TRIP (SP → CAMPINAS, 80 km/h)
  //
  // A realistic 20-point journey on the Bandeirantes highway.
  // Segment spacing: ~2.2 km per 100s (80 km/h = 2222 cm/s).
  // All heuristics MUST remain silent — zero spoofing signals.
  // =========================================================================
  group('FALSE POSITIVE · REAL TRIP SP→Campinas 80 km/h', () {
    test('FP-01: realistic highway route produces zero signals and zero risk', () {
      // Route: SP Tietê Terminal → Campinas — Rodovia dos Bandeirantes (SP-348)
      // Approximate bearing: NW. Step: 0.02° lat, 0.01° lng ≈ 2.3 km per step.
      // Speed: 2222 cm/s (80 km/h). Interval: 100 s between pings.
      // Accuracy: realistic variation 8–14 m. Heading: realistic NW corridor with minor noise.
      final t0 = DateTime.utc(2026, 4, 14, 7, 0, 0);

      // Physical Metric - Double Required
      final facts = [
        fact(
          ts: t0,
          lat: -23.5158,
          lng: -46.6258,
          speedCms: 2222,
          accuracyMeters: 10.2,
          headingDegrees: 312,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 100)),
          lat: -23.4958,
          lng: -46.6158,
          speedCms: 2180,
          accuracyMeters: 8.7,
          headingDegrees: 310,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 200)),
          lat: -23.4758,
          lng: -46.6058,
          speedCms: 2260,
          accuracyMeters: 12.1,
          headingDegrees: 314,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 300)),
          lat: -23.4558,
          lng: -46.5958,
          speedCms: 2200,
          accuracyMeters: 9.5,
          headingDegrees: 311,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 400)),
          lat: -23.4358,
          lng: -46.5858,
          speedCms: 2240,
          accuracyMeters: 11.3,
          headingDegrees: 313,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 500)),
          lat: -23.4158,
          lng: -46.5758,
          speedCms: 2190,
          accuracyMeters: 8.2,
          headingDegrees: 309,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 600)),
          lat: -23.3958,
          lng: -46.5658,
          speedCms: 2270,
          accuracyMeters: 13.4,
          headingDegrees: 315,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 700)),
          lat: -23.3758,
          lng: -46.5558,
          speedCms: 2210,
          accuracyMeters: 9.9,
          headingDegrees: 311,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 800)),
          lat: -23.3558,
          lng: -46.5458,
          speedCms: 2250,
          accuracyMeters: 10.7,
          headingDegrees: 314,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 900)),
          lat: -23.3358,
          lng: -46.5358,
          speedCms: 2195,
          accuracyMeters: 8.8,
          headingDegrees: 310,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1000)),
          lat: -23.3158,
          lng: -46.5258,
          speedCms: 2230,
          accuracyMeters: 12.6,
          headingDegrees: 316,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1100)),
          lat: -23.2958,
          lng: -46.5158,
          speedCms: 2180,
          accuracyMeters: 9.1,
          headingDegrees: 312,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1200)),
          lat: -23.2758,
          lng: -46.5058,
          speedCms: 2260,
          accuracyMeters: 11.5,
          headingDegrees: 313,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1300)),
          lat: -23.2558,
          lng: -46.4958,
          speedCms: 2205,
          accuracyMeters: 8.4,
          headingDegrees: 309,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1400)),
          lat: -23.2358,
          lng: -46.4858,
          speedCms: 2245,
          accuracyMeters: 14.0,
          headingDegrees: 315,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1500)),
          lat: -23.2158,
          lng: -46.4758,
          speedCms: 2190,
          accuracyMeters: 9.6,
          headingDegrees: 311,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1600)),
          lat: -23.1958,
          lng: -46.4658,
          speedCms: 2270,
          accuracyMeters: 10.3,
          headingDegrees: 314,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1700)),
          lat: -23.1758,
          lng: -46.4558,
          speedCms: 2215,
          accuracyMeters: 8.9,
          headingDegrees: 310,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1800)),
          lat: -23.1558,
          lng: -46.4458,
          speedCms: 2240,
          accuracyMeters: 12.8,
          headingDegrees: 312,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 1900)),
          lat: -23.1358,
          lng: -46.4358,
          speedCms: 2200,
          accuracyMeters: 9.2,
          headingDegrees: 311,
        ),
      ];

      final risk = detector.analyze(facts);

      expect(
        risk.scoreBps,
        0,
        reason: 'FP-01: clean highway trip must produce ZERO risk score',
      );
      expect(
        risk.signals,
        isEmpty,
        reason: 'FP-01: clean highway trip must produce NO spoofing signals',
      );
      expect(
        risk.isSuspected(),
        isFalse,
        reason: 'FP-01: clean highway trip must NOT be flagged as suspected',
      );
    });
  });

  // =========================================================================
  // GROUP 5 — REGRESSION · Existing Heuristics
  //
  // Guards that the two new heuristics (impossiblePositionJump, temporalAnomaly)
  // do NOT break the three original detectors already covered in the test suite.
  // =========================================================================
  group('REGRESSION · Existing Heuristics', () {
    test(
      'REG-01: zero-entropy accuracy → zeroEntropyAccuracy (no new signals)',
      () {
        final t = DateTime.utc(2026, 4, 14, 12, 0, 0);
        // 10 pings, all same position, speed=0, accuracy identical → zeroEntropy fires.
        // Timestamps ascending → no temporal anomaly.
        // No movement → no position jump.
        final facts = [
          fact(
            ts: t,
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 0,
          ),
          fact(
            ts: t.add(const Duration(seconds: 10)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 1,
          ),
          fact(
            ts: t.add(const Duration(seconds: 20)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 2,
          ),
          fact(
            ts: t.add(const Duration(seconds: 30)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 3,
          ),
          fact(
            ts: t.add(const Duration(seconds: 40)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 4,
          ),
          fact(
            ts: t.add(const Duration(seconds: 50)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 5,
          ),
          fact(
            ts: t.add(const Duration(seconds: 60)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 6,
          ),
          fact(
            ts: t.add(const Duration(seconds: 70)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 7,
          ),
          fact(
            ts: t.add(const Duration(seconds: 80)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 8,
          ),
          fact(
            ts: t.add(const Duration(seconds: 90)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 8.54321,
            headingDegrees: 9,
          ),
        ];

        final risk = detector.analyze(facts);

        expect(risk.signals, contains(SpoofingSignal.zeroEntropyAccuracy));
        expect(risk.scoreBps, 4000);
        expect(
          risk.signals,
          isNot(contains(SpoofingSignal.impossiblePositionJump)),
          reason: 'REG-01: stationary facts must NOT trigger velocity guard',
        );
        expect(
          risk.signals,
          isNot(contains(SpoofingSignal.temporalAnomaly)),
          reason:
              'REG-01: ascending timestamps must NOT trigger temporal anomaly',
        );
      },
    );

    test(
      'REG-02: constant heading (20 pings) → perfectLinearTrajectory (no new signals)',
      () {
        final t = DateTime.utc(2026, 4, 14, 13, 0, 0);
        final facts = [
          fact(
            ts: t,
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 0,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 10)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 1,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 20)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 2,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 30)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 3,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 40)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 4,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 50)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 5,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 60)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 6,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 70)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 7,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 80)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 8,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 90)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 9,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 100)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 10,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 110)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 11,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 120)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 12,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 130)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 13,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 140)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 14,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 150)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 15,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 160)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 16,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 170)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 17,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 180)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 18,
            headingDegrees: 45,
          ),
          fact(
            ts: t.add(const Duration(seconds: 190)),
            lat: -23.5505,
            lng: -46.6333,
            speedCms: 0,
            accuracyMeters: 10.0 + 19,
            headingDegrees: 45,
          ),
        ];

        final risk = detector.analyze(facts);

        expect(risk.signals, contains(SpoofingSignal.perfectLinearTrajectory));
        expect(risk.scoreBps, 3000);
        expect(
          risk.signals,
          isNot(contains(SpoofingSignal.impossiblePositionJump)),
          reason: 'REG-02: stationary facts must NOT trigger velocity guard',
        );
        expect(risk.signals, isNot(contains(SpoofingSignal.temporalAnomaly)));
      },
    );

    test('REG-03: three original signals combined → clamped to 10000 bps', () {
      final t = DateTime.utc(2026, 4, 14, 14, 0, 0);
      // 20 facts: static position + speed (staticPositionWhileMoving),
      // identical accuracy (zeroEntropy), constant heading (perfectLinear).
      // Window: 0..1140s (19 min) > 5 min gate.
      final facts = [
        fact(
          ts: t,
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 60)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 120)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 180)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 240)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 300)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 360)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 420)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 480)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 540)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 600)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 660)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 720)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 780)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 840)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 900)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 960)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 1020)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 1080)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
        fact(
          ts: t.add(const Duration(seconds: 1140)),
          lat: -23.5505,
          lng: -46.6333,
          speedCms: 1500,
          accuracyMeters: 10.0,
          headingDegrees: 90,
        ),
      ];

      final risk = detector.analyze(facts);

      expect(risk.isSuspected(), isTrue);
      expect(
        risk.scoreBps,
        10000,
        reason: 'REG-03: 5000+4000+3000=12000 must clamp to 10000',
      );
      expect(risk.signals, hasLength(3));
    });

    test('REG-04: fewer than 5 facts → zero risk (insufficient window)', () {
      final t = DateTime.utc(2026, 4, 14, 15, 0, 0);
      final facts = [fact(ts: t, lat: -23.5505, lng: -46.6333)];

      final risk = detector.analyze(facts);

      expect(risk.scoreBps, 0);
      expect(risk.signals, isEmpty);
    });
  });

  // =========================================================================
  // GROUP 6 — ANTI-TAMPER · JIGGLE ATTACK
  //
  // Sophisticated attackers inject micro-noise to evade stillness detection.
  // The detector must use standard deviation analysis to catch artificial outliers.
  // =========================================================================
  group('ANTI-TAMPER · JIGGLE ATTACK', () {
    test(
      'JIGGLE-01: 9 identical coords + 1 outlier (2.5m) → staticPositionWhileMoving',
      () {
        // Anhanguera (Reta de Jundiaí) — hardcoded
        const double baseLat = -23.1857; // Physical Metric - Double Required
        const double baseLng = -46.8978; // Physical Metric - Double Required
        final t0 = DateTime.utc(2026, 4, 14, 16, 0, 0);

        final facts = [
          // Facts 0-8: identical coordinates, speed 50 km/h (1389 cm/s)
          fact(
            ts: t0,
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 10.2,
            headingDegrees: 45,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 60)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 9.8,
            headingDegrees: 47,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 120)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 11.1,
            headingDegrees: 43,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 180)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 9.5,
            headingDegrees: 46,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 240)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 10.7,
            headingDegrees: 44,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 300)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 9.2,
            headingDegrees: 48,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 360)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 11.4,
            headingDegrees: 42,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 420)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 8.9,
            headingDegrees: 49,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 480)),
            lat: baseLat,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 10.5,
            headingDegrees: 41,
          ),
          // Fact 9: outlier with +0.000025° lat offset (~2.8m) to attempt jiggle bypass
          fact(
            ts: t0.add(const Duration(seconds: 540)),
            lat: baseLat + 0.000025,
            lng: baseLng,
            speedCms: 1389,
            accuracyMeters: 9.7,
            headingDegrees: 45,
          ),
        ];

        final risk = detector.analyze(facts);

        expect(
          risk.signals,
          contains(SpoofingSignal.staticPositionWhileMoving),
          reason:
              'JIGGLE-01: stdDev analysis must detect artificial outlier injection',
        );
        expect(
          risk.scoreBps,
          greaterThanOrEqualTo(5000),
          reason: 'JIGGLE-01: staticPositionWhileMoving contributes 5000 bps',
        );
      },
    );
  });

  // =========================================================================
  // GROUP 7 — ANTI-TAMPER · TUNNEL/BUNKER EFFECT
  //
  // GPS blackout followed by impossible repositioning indicates device tampering.
  // Gap > 15 min + distance > 50 km triggers excessiveTemporalGap signal.
  // =========================================================================
  group('ANTI-TAMPER · TUNNEL/BUNKER EFFECT', () {
    test(
      'TUNNEL-01: BH→RJ 2-hour gap (430km) → excessiveTemporalGap (≥ 8000 bps)',
      () {
        final t0 = DateTime.utc(2026, 4, 14, 17, 0, 0);

        // Belo Horizonte (BR-040)
        const double bhLat = -19.9219; // Physical Metric - Double Required
        const double bhLng = -43.9333; // Physical Metric - Double Required
        // Rio de Janeiro (Linha Vermelha)
        const double rjLat = -22.9068; // Physical Metric - Double Required
        const double rjLng = -43.1729; // Physical Metric - Double Required

        final facts = [
          // Facts 0-2: Normal progression in Belo Horizonte
          fact(
            ts: t0,
            lat: bhLat,
            lng: bhLng,
            speedCms: 1000,
            accuracyMeters: 10.2,
            headingDegrees: 120,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 60)),
            lat: bhLat + 0.0001,
            lng: bhLng + 0.0001,
            speedCms: 1050,
            accuracyMeters: 9.8,
            headingDegrees: 122,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 120)),
            lat: bhLat + 0.0002,
            lng: bhLng + 0.0002,
            speedCms: 980,
            accuracyMeters: 11.1,
            headingDegrees: 118,
          ),
          // Fact 3: 2-hour gap (7200s) + teleport to Rio de Janeiro (~430 km)
          fact(
            ts: t0.add(const Duration(seconds: 7320)),
            lat: rjLat,
            lng: rjLng,
            speedCms: 1000,
            accuracyMeters: 9.5,
            headingDegrees: 120,
          ),
          fact(
            ts: t0.add(const Duration(seconds: 7380)),
            lat: rjLat + 0.0001,
            lng: rjLng + 0.0001,
            speedCms: 1020,
            accuracyMeters: 10.3,
            headingDegrees: 121,
          ),
        ];

        final risk = detector.analyze(facts);

        expect(
          risk.signals,
          contains(SpoofingSignal.excessiveTemporalGap),
          reason:
              'TUNNEL-01: 2-hour gap + 430km jump MUST flag excessiveTemporalGap',
        );
        expect(
          risk.scoreBps,
          greaterThanOrEqualTo(8000),
          reason: 'TUNNEL-01: excessiveTemporalGap weight = 8000 bps',
        );
        expect(
          risk.isSuspected(),
          isTrue,
          reason: 'TUNNEL-01: score must exceed 7000 bps suspicion threshold',
        );
      },
    );

    test('TUNNEL-02: 2-hour stop at same location → NO excessiveTemporalGap', () {
      final t0 = DateTime.utc(2026, 4, 14, 18, 0, 0);

      // Belo Horizonte (BR-040) — legitimate rest stop
      const double bhLat = -19.9219; // Physical Metric - Double Required
      const double bhLng = -43.9333; // Physical Metric - Double Required

      final facts = [
        fact(
          ts: t0,
          lat: bhLat,
          lng: bhLng,
          speedCms: 0,
          accuracyMeters: 10.2,
          headingDegrees: 0,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 60)),
          lat: bhLat,
          lng: bhLng,
          speedCms: 0,
          accuracyMeters: 9.8,
          headingDegrees: 0,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 120)),
          lat: bhLat,
          lng: bhLng,
          speedCms: 0,
          accuracyMeters: 11.1,
          headingDegrees: 0,
        ),
        // 2-hour gap but same location (legitimate rest)
        fact(
          ts: t0.add(const Duration(seconds: 7320)),
          lat: bhLat,
          lng: bhLng,
          speedCms: 0,
          accuracyMeters: 9.5,
          headingDegrees: 0,
        ),
        fact(
          ts: t0.add(const Duration(seconds: 7380)),
          lat: bhLat,
          lng: bhLng,
          speedCms: 0,
          accuracyMeters: 10.3,
          headingDegrees: 0,
        ),
      ];

      final risk = detector.analyze(facts);

      expect(
        risk.signals,
        isNot(contains(SpoofingSignal.excessiveTemporalGap)),
        reason:
            'TUNNEL-02: legitimate rest stop must NOT trigger temporal gap signal',
      );
      // Note: score could be 0 or low from other heuristics, but no temporal gap
    });
  });
}
