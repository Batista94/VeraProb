// Tests for the EvidencePayload sealed class hierarchy — Phase 9.4.4
//
// Validates that every subtype round-trips through toJson/fromJson and that
// the `_type` discriminator routes correctly in EvidencePayload.fromJson.
// GenericEvidencePayload fallback is tested for legacy (no `_type`) records.

import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/sla_audit/evidence_payload.dart';

void main() {
  group('EvidencePayload sealed class', () {
    // ── DwellRequirementEvidence ─────────────────────────────────────────
    group('DwellRequirementEvidence', () {
      test('toJson emits _type discriminator and fields', () {
        const evidence = DwellRequirementEvidence(
          requiredDwellSeconds: 120,
          parameterSource: 'rule_config',
        );
        final json = evidence.toJson();
        expect(json['_type'], 'dwell_requirement');
        expect(json['required_dwell_seconds'], 120);
        expect(json['parameter_source'], 'rule_config');
      });

      test('fromJson restores instance from json', () {
        final json = {
          '_type': 'dwell_requirement',
          'required_dwell_seconds': 90,
          'parameter_source': 'rule_config',
        };
        final evidence =
            EvidencePayload.fromJson(json) as DwellRequirementEvidence;
        expect(evidence.requiredDwellSeconds, 90);
        expect(evidence.parameterSource, 'rule_config');
      });

      test('round-trip preserves all fields', () {
        const original = DwellRequirementEvidence(
          requiredDwellSeconds: 60,
          parameterSource: 'default',
        );
        final restored =
            EvidencePayload.fromJson(original.toJson()) as DwellRequirementEvidence;
        expect(restored.requiredDwellSeconds, original.requiredDwellSeconds);
        expect(restored.parameterSource, original.parameterSource);
      });
    });

    // ── SpeedViolationEvidence ───────────────────────────────────────────
    group('SpeedViolationEvidence', () {
      test('toJson emits _type discriminator and fields', () {
        const evidence = SpeedViolationEvidence(
          actualSpeedKmh: 95.5,
          limitSpeedKmh: 80.0,
        );
        final json = evidence.toJson();
        expect(json['_type'], 'speed_violation');
        expect(json['actual_speed_kmh'], 95.5);
        expect(json['limit_speed_kmh'], 80.0);
      });

      test('fromJson restores instance with num cast to double', () {
        final json = {
          '_type': 'speed_violation',
          'actual_speed_kmh': 110,   // int in JSON
          'limit_speed_kmh': 100,    // int in JSON
        };
        final evidence =
            EvidencePayload.fromJson(json) as SpeedViolationEvidence;
        expect(evidence.actualSpeedKmh, 110.0);
        expect(evidence.limitSpeedKmh, 100.0);
      });

      test('round-trip preserves all fields', () {
        const original = SpeedViolationEvidence(
          actualSpeedKmh: 130.5,
          limitSpeedKmh: 120.0,
        );
        final restored =
            EvidencePayload.fromJson(original.toJson()) as SpeedViolationEvidence;
        expect(restored.actualSpeedKmh, original.actualSpeedKmh);
        expect(restored.limitSpeedKmh, original.limitSpeedKmh);
      });
    });

    // ── GeofenceBindingEvidence ──────────────────────────────────────────
    group('GeofenceBindingEvidence', () {
      test('toJson emits _type discriminator and fields', () {
        const evidence = GeofenceBindingEvidence(
          distanceMeters: 12.5,
          allowedRadiusMeters: 50,
          actualDwellSeconds: 45,
          requiredDwellSeconds: 30,
        );
        final json = evidence.toJson();
        expect(json['_type'], 'geofence_binding');
        expect(json['distance_meters'], 12.5);
        expect(json['allowed_radius_meters'], 50);
        expect(json['actual_dwell_seconds'], 45);
        expect(json['required_dwell_seconds'], 30);
      });

      test('round-trip preserves all fields', () {
        const original = GeofenceBindingEvidence(
          distanceMeters: 8.3,
          allowedRadiusMeters: 100,
          actualDwellSeconds: 120,
          requiredDwellSeconds: 60,
        );
        final restored =
            EvidencePayload.fromJson(original.toJson()) as GeofenceBindingEvidence;
        expect(restored.distanceMeters, original.distanceMeters);
        expect(restored.allowedRadiusMeters, original.allowedRadiusMeters);
        expect(restored.actualDwellSeconds, original.actualDwellSeconds);
        expect(restored.requiredDwellSeconds, original.requiredDwellSeconds);
      });
    });

    // ── PenaltyAssessedEvidence ──────────────────────────────────────────
    group('PenaltyAssessedEvidence', () {
      test('toJson emits _type and penalty_amount_cents', () {
        const evidence = PenaltyAssessedEvidence(penaltyAmountCents: 50000);
        final json = evidence.toJson();
        expect(json['_type'], 'penalty_assessed');
        expect(json['penalty_amount_cents'], 50000);
      });

      test('toJson handles null penalty', () {
        const evidence = PenaltyAssessedEvidence();
        final json = evidence.toJson();
        expect(json['penalty_amount_cents'], isNull);
      });

      test('round-trip preserves non-null penalty', () {
        const original = PenaltyAssessedEvidence(penaltyAmountCents: 150000);
        final restored =
            EvidencePayload.fromJson(original.toJson()) as PenaltyAssessedEvidence;
        expect(restored.penaltyAmountCents, 150000);
      });
    });

    // ── ExpirationSweepEvidence ──────────────────────────────────────────
    group('ExpirationSweepEvidence', () {
      test('toJson emits _type discriminator and all fields', () {
        const evidence = ExpirationSweepEvidence(
          scheduledWindowEndUtc: '2026-03-01T08:00:00.000Z',
          evaluatedAtUtc: '2026-03-01T09:15:00.000Z',
          expiredBySeconds: 4500,
        );
        final json = evidence.toJson();
        expect(json['_type'], 'expiration_sweep');
        expect(json['scheduled_window_end_utc'], '2026-03-01T08:00:00.000Z');
        expect(json['evaluated_at_utc'], '2026-03-01T09:15:00.000Z');
        expect(json['expired_by_seconds'], 4500);
      });

      test('round-trip preserves all fields', () {
        const original = ExpirationSweepEvidence(
          scheduledWindowEndUtc: '2026-04-01T06:00:00.000Z',
          evaluatedAtUtc: '2026-04-01T06:05:00.000Z',
          expiredBySeconds: 300,
        );
        final restored =
            EvidencePayload.fromJson(original.toJson()) as ExpirationSweepEvidence;
        expect(restored.scheduledWindowEndUtc, original.scheduledWindowEndUtc);
        expect(restored.evaluatedAtUtc, original.evaluatedAtUtc);
        expect(restored.expiredBySeconds, original.expiredBySeconds);
      });
    });

    // ── GenericEvidencePayload (legacy fallback) ─────────────────────────
    group('GenericEvidencePayload — legacy fallback', () {
      test('fromJson falls back to GenericEvidencePayload when _type is absent', () {
        final legacyJson = {'some_old_key': 'some_old_value', 'count': 3};
        final evidence = EvidencePayload.fromJson(legacyJson);
        expect(evidence, isA<GenericEvidencePayload>());
        final generic = evidence as GenericEvidencePayload;
        expect(generic.rawData['some_old_key'], 'some_old_value');
        expect(generic.rawData['count'], 3);
      });

      test('fromJson falls back when _type is an unknown string', () {
        final json = {'_type': 'unknown_future_type', 'data': 42};
        final evidence = EvidencePayload.fromJson(json);
        expect(evidence, isA<GenericEvidencePayload>());
      });

      test('GenericEvidencePayload.toJson returns rawData unchanged', () {
        final rawData = {'_type': 'legacy', 'value': 99};
        final evidence = GenericEvidencePayload(rawData);
        expect(evidence.toJson(), same(rawData));
      });
    });
  });
}
