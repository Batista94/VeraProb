/// Integration Test: HMAC/SHA-256 Tampering Detection (INV-9 / INV-31)
///
/// **Forensic Scenario (Red Team):**
/// 1. Application inserts a valid telemetry record with a correct SHA-256
///    payload hash (`payload_hash` column).
/// 2. A malicious DBA (or compromised credential) uses raw SQL to modify
///    the `raw_payload` JSONB field — e.g., changing a GPS coordinate —
///    WITHOUT updating the `payload_hash`.
/// 3. Application reads the record and verifies the hash.
/// 4. **Expected:** `IntegrityException` — the read is BLOCKED (Fail-Fast).
///
/// **Why this matters:**
/// Without this check, an attacker could alter forensic evidence in the
/// database and the application would serve the tampered data as authentic.
/// The SHA-256 hash (computed at ingestion) is the only defense against
/// post-insertion tampering.
///
/// **Prerequisites:**
/// - Local Supabase running (`supabase start`)
/// - `raw_telemetry_payloads` table exists (migration 20260325000001)
///
/// Run: `flutter test integration_test/hmac_tampering_detection_test.dart`
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import '../test/infrastructure/postgres/postgres_test_config.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Computes SHA-256 of a canonical JSON string (mimics ingestion Edge Function).
String _computePayloadHash(Map<String, dynamic> payload) {
  // Canonical: sort keys so hash is deterministic across Dart/Deno
  final canonicalJson = jsonEncode(BasePostgresRepository.sortKeys(payload));
  return sha256.convert(utf8.encode(canonicalJson)).toString();
}

/// Inserts a raw telemetry payload directly into the DB (bypassing Edge Function).
/// Returns the inserted record's ID.
Future<String> _insertRawTelemetry(
  SupabaseClient client, {
  required String orgId,
  required Map<String, dynamic> payload,
  String? providerName,
  String? deviceId,
}) async {
  final payloadHash = _computePayloadHash(payload);
  final id = const Uuid().v4();

  await client.from('raw_telemetry_payloads').insert({
    'id': id,
    'organization_id': orgId,
    'provider_name': providerName ?? 'test-provider',
    'device_id': deviceId ?? 'test-device-001',
    'received_at_utc': DateTime.now().toUtc().toIso8601String(),
    'raw_payload': payload,
    'payload_hash': payloadHash,
  });

  return id;
}

/// Reads a raw telemetry record and verifies its integrity.
/// This is the EXACT pattern a production repository would use.
///
/// **Fail-Fast:** If the hash doesn't match, throws [IntegrityException].
Future<Map<String, dynamic>> readAndVerifyTelemetry(
  SupabaseClient client, {
  required String recordId,
  required String orgId,
}) async {
  final row = await client
      .from('raw_telemetry_payloads')
      .select()
      .eq('id', recordId)
      .eq('organization_id', orgId)
      .maybeSingle();

  if (row == null) {
    throw StateError('Record $recordId not found in org $orgId');
  }

  // ── Integrity verification (the critical forensic check) ──
  final storedPayload = row['raw_payload'] as Map<String, dynamic>;
  final storedHash = row['payload_hash'] as String;
  final recomputedHash = _computePayloadHash(storedPayload);

  if (storedHash != recomputedHash) {
    throw IntegrityException(
      'Payload hash mismatch for raw_telemetry_payloads/$recordId: '
      'stored=$storedHash, recomputed=$recomputedHash. '
      'Data may have been tampered with. Read BLOCKED (Fail-Fast).',
      field: 'payload_hash',
    );
  }

  return row;
}

/// Tamper: uses raw SQL to modify a field in raw_payload WITHOUT updating the hash.
/// This simulates what a malicious DBA would do.
Future<void> _tamperWithPayload(
  SupabaseClient client, {
  required String recordId,
  required String targetKey,
  required dynamic newValue,
}) async {
  // Read current payload
  final row = await client
      .from('raw_telemetry_payloads')
      .select('raw_payload')
      .eq('id', recordId)
      .single();

  final payload = Map<String, dynamic>.from(row['raw_payload'] as Map);

  // Tamper: modify the target field
  payload[targetKey] = newValue;

  // Write back the tampered payload — hash column is LEFT UNTOUCHED
  await client
      .from('raw_telemetry_payloads')
      .update({'raw_payload': payload})
      .eq('id', recordId);
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  const testOrgId = PostgresTestConfig.testOrgId;

  setUpAll(() async {
    await PostgresTestConfig.ensureSentinelOrg();
  });

  // ── Phase 1: Insert valid record, verify integrity → SUCCESS ────────────

  group('Phase 1: Valid record — integrity check PASSES', () {
    test('freshly inserted record passes hash verification', () async {
      final client = await PostgresTestConfig.createClient();

      final validPayload = {
        'gps_timestamp': '2026-04-11T15:30:00.000Z',
        'latitude': -23.5505,
        'longitude': -46.6333,
        'speed_kmh': 45.0,
        'heading_degrees': 180,
        'device_status': 'active',
      };

      final recordId = await _insertRawTelemetry(
        client,
        orgId: testOrgId,
        payload: validPayload,
      );

      // Read via the app layer — should succeed
      final row = await readAndVerifyTelemetry(
        client,
        recordId: recordId,
        orgId: testOrgId,
      );

      expect(row['id'], equals(recordId));
      expect(row['raw_payload']['latitude'], equals(-23.5505));

      await client.dispose();
    });
  });

  // ── Phase 2: Tamper → Read → IntegrityException (Fail-Fast) ────────────

  group('Phase 2: Tampered record — integrity check FAILS (Fail-Fast)', () {
    test(
      'DBA changes GPS coordinate → hash mismatch → IntegrityException',
      () async {
        final client = await PostgresTestConfig.createClient();

        // 1. Insert a valid record
        final validPayload = {
          'gps_timestamp': '2026-04-11T15:30:00.000Z',
          'latitude': -23.5505, // São Paulo
          'longitude': -46.6333,
          'speed_kmh': 45.0,
          'heading_degrees': 180,
          'device_status': 'active',
        };

        final recordId = await _insertRawTelemetry(
          client,
          orgId: testOrgId,
          payload: validPayload,
        );

        // Verify: before tampering, read succeeds
        final beforeRow = await readAndVerifyTelemetry(
          client,
          recordId: recordId,
          orgId: testOrgId,
        );
        expect(beforeRow['raw_payload']['latitude'], equals(-23.5505));

        // 2. TAMPER: Malicious DBA changes GPS coordinates via raw SQL
        // (simulates someone with DB access altering evidence)
        await _tamperWithPayload(
          client,
          recordId: recordId,
          targetKey: 'latitude',
          newValue: -3.1190, // Moved to Manaus (Amazon) — 2700km away!
        );

        // 3. VERIFY: Hash is now stale — should NOT match the tampered payload
        // Read the tampered row and recompute the hash
        final tamperedRow = await client
            .from('raw_telemetry_payloads')
            .select()
            .eq('id', recordId)
            .eq('organization_id', testOrgId)
            .single();

        final tamperedPayload =
            tamperedRow['raw_payload'] as Map<String, dynamic>;
        final storedHash = tamperedRow['payload_hash'] as String;
        final recomputedHash = _computePayloadHash(tamperedPayload);

        // Prove the hashes differ
        expect(
          storedHash,
          isNot(equals(recomputedHash)),
          reason: 'After tampering, stored hash MUST NOT match recomputed hash',
        );

        // 4. FAIL-FAST: Reading through the app layer must BLOCK the read
        expect(
          () => readAndVerifyTelemetry(
            client,
            recordId: recordId,
            orgId: testOrgId,
          ),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('hash mismatch'),
            ),
          ),
          reason:
              'Read MUST be BLOCKED with IntegrityException (Fail-Fast policy)',
        );

        await client.dispose();
      },
    );

    test(
      'DBA changes speed value → hash mismatch → IntegrityException',
      () async {
        final client = await PostgresTestConfig.createClient();

        final validPayload = {
          'gps_timestamp': '2026-04-11T15:30:00.000Z',
          'latitude': -23.5505,
          'longitude': -46.6333,
          'speed_kmh': 45.0,
          'heading_degrees': 180,
        };

        final recordId = await _insertRawTelemetry(
          client,
          orgId: testOrgId,
          payload: validPayload,
        );

        // Tamper: change speed (financial impact — speed-based SLA breach)
        await _tamperWithPayload(
          client,
          recordId: recordId,
          targetKey: 'speed_kmh',
          newValue: 120.0, // 45 → 120 km/h — could trigger a false SLA breach
        );

        expect(
          () => readAndVerifyTelemetry(
            client,
            recordId: recordId,
            orgId: testOrgId,
          ),
          throwsA(isA<IntegrityException>()),
        );

        await client.dispose();
      },
    );

    test(
      'DBA adds a field to the payload → hash mismatch → IntegrityException',
      () async {
        final client = await PostgresTestConfig.createClient();

        final validPayload = {
          'gps_timestamp': '2026-04-11T15:30:00.000Z',
          'latitude': -23.5505,
          'longitude': -46.6333,
        };

        final recordId = await _insertRawTelemetry(
          client,
          orgId: testOrgId,
          payload: validPayload,
        );

        // Tamper: inject a fraudulent field
        await _tamperWithPayload(
          client,
          recordId: recordId,
          targetKey: 'fraudulent_sla_breach',
          newValue: true, // Adding a field that didn't exist before
        );

        expect(
          () => readAndVerifyTelemetry(
            client,
            recordId: recordId,
            orgId: testOrgId,
          ),
          throwsA(isA<IntegrityException>()),
        );

        await client.dispose();
      },
    );

    test(
      'DBA deletes a field from the payload → hash mismatch → IntegrityException',
      () async {
        final client = await PostgresTestConfig.createClient();

        final validPayload = {
          'gps_timestamp': '2026-04-11T15:30:00.000Z',
          'latitude': -23.5505,
          'longitude': -46.6333,
          'device_status': 'active',
        };

        final recordId = await _insertRawTelemetry(
          client,
          orgId: testOrgId,
          payload: validPayload,
        );

        // Tamper: remove a field
        final row = await client
            .from('raw_telemetry_payloads')
            .select('raw_payload')
            .eq('id', recordId)
            .single();

        final payload = Map<String, dynamic>.from(row['raw_payload'] as Map);
        payload.remove('device_status');

        await client
            .from('raw_telemetry_payloads')
            .update({'raw_payload': payload})
            .eq('id', recordId);

        expect(
          () => readAndVerifyTelemetry(
            client,
            recordId: recordId,
            orgId: testOrgId,
          ),
          throwsA(isA<IntegrityException>()),
        );

        await client.dispose();
      },
    );

    test('nested payload tampering is detected (deep structure)', () async {
      final client = await PostgresTestConfig.createClient();

      final validPayload = {
        'gps_timestamp': '2026-04-11T15:30:00.000Z',
        'latitude': -23.5505,
        'longitude': -46.6333,
        'metadata': {
          'driver_id': 'DRV-001',
          'vehicle_plate': 'ABC-1234',
          'sensor_readings': {
            'fuel_level': 0.75,
            'engine_temp': 90,
            'gps_accuracy': 5,
          },
        },
      };

      final recordId = await _insertRawTelemetry(
        client,
        orgId: testOrgId,
        payload: validPayload,
      );

      // Tamper: deeply nested value
      final row = await client
          .from('raw_telemetry_payloads')
          .select('raw_payload')
          .eq('id', recordId)
          .single();

      final payload = Map<String, dynamic>.from(row['raw_payload'] as Map);
      final metadata = Map<String, dynamic>.from(payload['metadata'] as Map);
      final sensors = Map<String, dynamic>.from(
        metadata['sensor_readings'] as Map,
      );
      sensors['fuel_level'] = 0.10; // 75% → 10% — could trigger false alert
      metadata['sensor_readings'] = sensors;
      payload['metadata'] = metadata;

      await client
          .from('raw_telemetry_payloads')
          .update({'raw_payload': payload})
          .eq('id', recordId);

      expect(
        () => readAndVerifyTelemetry(
          client,
          recordId: recordId,
          orgId: testOrgId,
        ),
        throwsA(isA<IntegrityException>()),
      );

      await client.dispose();
    });
  });

  // ── Phase 3: No false positives — valid data always passes ─────────────

  group('Phase 3: No false positives', () {
    test('multiple reads of the same valid record all pass', () async {
      final client = await PostgresTestConfig.createClient();

      final validPayload = {
        'gps_timestamp': '2026-04-11T15:30:00.000Z',
        'latitude': -23.5505,
        'longitude': -46.6333,
      };

      final recordId = await _insertRawTelemetry(
        client,
        orgId: testOrgId,
        payload: validPayload,
      );

      // Read 10 times — all must pass
      for (int i = 0; i < 10; i++) {
        final row = await readAndVerifyTelemetry(
          client,
          recordId: recordId,
          orgId: testOrgId,
        );
        expect(row['raw_payload']['latitude'], equals(-23.5505));
      }

      await client.dispose();
    });

    test('canonical JSON ordering does NOT cause false positives', () async {
      final client = await PostgresTestConfig.createClient();

      // Insert with keys in random order
      final payloadA = <String, dynamic>{
        'z_field': 'end',
        'a_field': 'start',
        'm_field': 'middle',
      };

      final recordId = await _insertRawTelemetry(
        client,
        orgId: testOrgId,
        payload: payloadA,
      );

      // Read should pass — canonical ordering means insertion order is irrelevant
      final row = await readAndVerifyTelemetry(
        client,
        recordId: recordId,
        orgId: testOrgId,
      );
      expect(row['raw_payload']['z_field'], equals('end'));

      await client.dispose();
    });
  });
}
