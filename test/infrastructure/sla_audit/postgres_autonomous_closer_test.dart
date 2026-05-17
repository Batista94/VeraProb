// =============================================================================
// Test: postgres_autonomous_closer_test.dart
// C5: Full adversarial suite for Workstream A + C (Phase 10).
//
// Covers:
//   check_and_close_execution_autonomously (Workstream A)
//   process_gps_for_execution_transitions  (Workstream C)
//   ingest-sascar INV-6 denial             (Workstream B / C4)
//
// INV-1:  org_id on all queries.
// INV-3:  APPEND-ONLY ledger (SYSTEM_AUTO_CLOSE / SYSTEM_AUTO_START).
// INV-6:  TIMESTAMPTZ — destination_zone_entered_at_utc.
// INV-15: CAS first-write-wins (EDGE-5 race test).
// INV-22: Tenant isolation.
// INV-26: not_found == wrong_org (EDGE-6).
// =============================================================================

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../postgres/postgres_test_config.dart';

// ── Geographic constants (INV-12) ─────────────────────────────────────────────

// Destination zone: São Paulo city-centre test area.
const double _destLat = -23.5505; // Physical Metric - Double Required
const double _destLng = -46.6333; // Physical Metric - Double Required
const int _destRadius = 100; // metres

// Origin zone: ~1 km south-west of dest.
const double _origLat = -23.5600; // Physical Metric - Double Required
const double _origLng = -46.6400; // Physical Metric - Double Required
const int _origRadius = 100; // metres

// GPS inside dest zone (exact centre → distance = 0).
const double _inDestLat = -23.5505; // Physical Metric - Double Required
const double _inDestLng = -46.6333; // Physical Metric - Double Required

// GPS outside dest zone (~222 m north → outside 100 m radius).
// 0.002° latitude ≈ 222 m at ~23°S.
const double _outDestLat = -23.5485; // Physical Metric - Double Required
const double _outDestLng = -46.6333; // Physical Metric - Double Required

// GPS inside origin zone (exact centre).
const double _inOrigLat = -23.5600; // Physical Metric - Double Required
const double _inOrigLng = -46.6400; // Physical Metric - Double Required

// ── Fixture data class ────────────────────────────────────────────────────────

class _Fixture {
  const _Fixture({
    required this.orgId,
    required this.setId,
    required this.contractId,
    this.originZoneId,
    this.destZoneId,
    this.vehicleId,
    this.vehiclePlate,
    this.deviceSerial,
  });

  final String orgId;
  final String setId;
  final String contractId;
  final String? originZoneId;
  final String? destZoneId;
  final String? vehicleId;
  final String? vehiclePlate;
  final String? deviceSerial;
}

// ── Seed helpers ──────────────────────────────────────────────────────────────

Future<_Fixture> _seed(
  SupabaseClient client, {
  required String orgId,
  String status = 'inTransit',
  bool withOriginZone = false,
  bool withDestZone = true,
  String? deviceSerial,
}) async {
  const uuid = Uuid();
  final setId = uuid.v4();
  final contractId = uuid.v4();
  final planId = uuid.v4();
  final now = DateTime.now().toUtc();
  final windowStart = now.subtract(const Duration(minutes: 5));
  final windowEnd = now.add(const Duration(hours: 2));

  await PostgresTestConfig.ensureSentinelOrg(id: orgId);

  String? origZoneId;
  if (withOriginZone) {
    final row = await client
        .from('operational_zones')
        .insert({
          'organization_id': orgId,
          'name': 'Orig-${uuid.v4().substring(0, 8)}',
          'latitude': _origLat,
          'longitude': _origLng,
          'radius_meters': _origRadius,
        })
        .select('id')
        .single();
    origZoneId = row['id'] as String;
  }

  String? destZoneId;
  if (withDestZone) {
    final row = await client
        .from('operational_zones')
        .insert({
          'organization_id': orgId,
          'name': 'Dest-${uuid.v4().substring(0, 8)}',
          'latitude': _destLat,
          'longitude': _destLng,
          'radius_meters': _destRadius,
        })
        .select('id')
        .single();
    destZoneId = row['id'] as String;
  }

  String? vehicleId;
  String? vehiclePlate;
  if (deviceSerial != null) {
    vehiclePlate = 'VEH-${orgId.substring(0, 8).toUpperCase()}';
    final row = await client
        .from('vehicles')
        .insert({
          'organization_id': orgId,
          'plate': vehiclePlate,
          'device_serial': deviceSerial,
          'status': 'available',
        })
        .select('id')
        .single();
    vehicleId = row['id'] as String;
  }

  await client.from('plan_declarations').insert({
    'id': planId,
    'contract_id': contractId,
    'organization_id': orgId,
    'declared_at_utc': now.toIso8601String(),
    'declared_by_user_id': 'seed-user',
    'plan_version': 1,
    'original_file_hash': PostgresTestConfig.fakeForensicHash(setId),
  });

  await client.from('contractual_service_executions').insert({
    'set_id': setId,
    'plan_declaration_id': planId,
    'organization_id': orgId,
    'scheduled_start_time_utc': windowStart.toIso8601String(),
    'scheduled_end_time_utc': windowEnd.toIso8601String(),
    'start_latitude': _origLat,
    'start_longitude': _origLng,
    'start_radius_meters': _origRadius,
    'end_latitude': _destLat,
    'end_longitude': _destLng,
    'end_radius_meters': _destRadius,
    'contractual_value_cents': 150000,
    'no_show_penalty_multiplier': 1.5,
    // ignore: use_null_aware_elements
    if (origZoneId != null) 'origin_zone_id': origZoneId,
    // ignore: use_null_aware_elements
    if (destZoneId != null) 'destination_zone_id': destZoneId,
  });

  await client.from('execution_states').insert({
    'id': uuid.v4(),
    'organization_id': orgId,
    'set_id': setId,
    'contract_id': contractId,
    'plan_version': 1,
    'start_latitude': _origLat,
    'start_longitude': _origLng,
    'start_radius_meters': _origRadius,
    'contractual_value_cents': 150000,
    'no_show_penalty_multiplier': 1.5,
    'window_start_utc': windowStart.toIso8601String(),
    'window_end_utc': windowEnd.toIso8601String(),
    'status': status,
    // ignore: use_null_aware_elements
    if (vehicleId != null) 'planned_vehicle_id': vehicleId,
    'created_at_utc': now.toIso8601String(),
    'last_evaluated_at_utc': now.toIso8601String(),
    'status_last_updated_at_utc': now.toIso8601String(),
  });

  return _Fixture(
    orgId: orgId,
    setId: setId,
    contractId: contractId,
    originZoneId: origZoneId,
    destZoneId: destZoneId,
    vehicleId: vehicleId,
    vehiclePlate: vehiclePlate,
    deviceSerial: deviceSerial,
  );
}

Future<void> _seedEvidenceRule(
  SupabaseClient client, {
  required String orgId,
  required String contractId,
  required List<String> types,
}) async {
  const uuid = Uuid();
  final ruleSetId = uuid.v4();
  final now = DateTime.now().toUtc();

  await client.from('contract_rule_sets').insert({
    'id': ruleSetId,
    'organization_id': orgId,
    'contract_id': contractId,
    'created_at_utc': now.toIso8601String(),
  });

  await client.from('contract_rule_versions').insert({
    'id': uuid.v4(),
    'rule_set_id': ruleSetId,
    'rule_type': 'REQUIRED_EVIDENCE',
    'rule_config': {'types': types},
    'rule_version': 1,
    'evaluation_order': 1,
    'active_from_utc': now.toIso8601String(),
    // active_to_utc intentionally omitted → NULL → currently active
  });
}

Future<void> _seedEvidence(
  SupabaseClient client, {
  required String orgId,
  required String setId,
  required String driverId,
  required String category,
}) async {
  const uuid = Uuid();
  final uploadId = uuid.v4();
  final now = DateTime.now().toUtc();

  await client.from('telegram_evidence_uploads').insert({
    'id': uploadId,
    'organization_id': orgId,
    'driver_id': driverId,
    'linked_set_id': setId,
    'chat_id': 100000001,
    'telegram_message_id': uploadId.hashCode.abs() % 999999 + 1,
    'file_name': '$category-$uploadId.jpg',
    'forensic_hash': PostgresTestConfig.fakeForensicHash('$setId-$category'),
    'storage_path': '$orgId/telegram/100000001/$uploadId.jpg',
    'source': 'telegram',
    'requires_manual_link': false,
    'uploaded_at_utc': now.toIso8601String(),
    'telegram_message_date': now.toIso8601String(),
    'mime_type': 'image/jpeg',
  });

  await client.from('telegram_evidence_categories').insert({
    'evidence_upload_id': uploadId,
    'organization_id': orgId,
    'category': category,
    'tagged_at_utc': now.toIso8601String(),
  });
}

// Derives a per-org SASCAR API key and seeds it into provider_api_keys.
// Returns the raw key to use in Authorization header.
Future<String> _seedSascarKey(SupabaseClient client, String orgId) async {
  final rawKey = 'test-sascar-inv6-key-$orgId';
  final keyHash = sha256.convert(utf8.encode(rawKey)).toString();

  await client.from('provider_api_keys').insert({
    'organization_id': orgId,
    'provider_name': 'SASCAR',
    'api_key_hash': keyHash,
    'is_active': true,
    'description': 'INV-6 test key',
  });

  return rawKey;
}

// ── Main ──────────────────────────────────────────────────────────────────────

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  final isFnRunning = await PostgresTestConfig.isEdgeFunctionsRunning();

  // ── DoD: Happy Path ─────────────────────────────────────────────────────────

  group(
    'Autonomous Closer — DoD: Happy Path',
    skip: !isRunning ? 'Supabase not running locally' : null,
    () {
      late SupabaseClient sc;

      setUpAll(() {
        sc = PostgresTestConfig.createServiceRoleClient();
      });

      tearDownAll(() async {
        await sc.dispose();
      });

      // DOD-1 + DOD-3 merged: dwell triggers close; audit has system actor.
      test('DOD-1/3: zero-evidence execution closes after 5-min dwell; '
          'sla_audit_ledger actor_type=system, actor_id=NULL', () async {
        const uuid = Uuid();
        final orgId = uuid.v4();
        final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

        // First call: dwell < 300 s → dwell_pending + sets entered_at.
        final r1 = await sc.rpc<Map<String, dynamic>>(
          'check_and_close_execution_autonomously',
          params: {
            'p_org_id': fx.orgId,
            'p_set_id': fx.setId,
            'p_current_lat': _inDestLat,
            'p_current_lng': _inDestLng,
          },
        );

        expect(r1['result'], equals('dwell_pending'));

        // CAS first-write-wins: entered_at must now be set (INV-15).
        final esRow1 = await sc
            .from('execution_states')
            .select('destination_zone_entered_at_utc')
            .eq('set_id', fx.setId)
            .single();
        expect(esRow1['destination_zone_entered_at_utc'], isNotNull);

        // Backdate dwell to 6 minutes → surpass 300 s threshold.
        await sc
            .from('execution_states')
            .update({
              'destination_zone_entered_at_utc': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(minutes: 6))
                  .toIso8601String(),
            })
            .eq('set_id', fx.setId)
            .eq('organization_id', fx.orgId);

        // Second call: dwell ≥ 300 s → closed.
        final r2 = await sc.rpc<Map<String, dynamic>>(
          'check_and_close_execution_autonomously',
          params: {
            'p_org_id': fx.orgId,
            'p_set_id': fx.setId,
            'p_current_lat': _inDestLat,
            'p_current_lng': _inDestLng,
          },
        );

        expect(r2['result'], equals('closed'));

        final esRow2 = await sc
            .from('execution_states')
            .select('status')
            .eq('set_id', fx.setId)
            .single();
        expect(esRow2['status'], equals('completed'));

        // DOD-3: audit actor columns (INV-3 append-only, C3 system rows).
        final ledger = await sc
            .from('sla_audit_ledger')
            .select('type, actor_type, actor_id')
            .eq('set_id', fx.setId)
            .eq('type', 'SYSTEM_AUTO_CLOSE');

        expect(ledger.length, equals(1));
        expect(ledger.first['actor_type'], equals('system'));
        expect(ledger.first['actor_id'], isNull);
      });

      test(
        'DOD-2: Carga instant close — all required evidence present → closed immediately',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

          await _seedEvidenceRule(
            sc,
            orgId: fx.orgId,
            contractId: fx.contractId,
            types: ['lacre'],
          );

          final driverId = await PostgresTestConfig.seedDriver(
            sc,
            orgId: fx.orgId,
          );
          await _seedEvidence(
            sc,
            orgId: fx.orgId,
            setId: fx.setId,
            driverId: driverId,
            category: 'lacre',
          );

          final r = await sc.rpc<Map<String, dynamic>>(
            'check_and_close_execution_autonomously',
            params: {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              'p_current_lat': _inDestLat,
              'p_current_lng': _inDestLng,
            },
          );

          expect(r['result'], equals('closed'));

          final esRow = await sc
              .from('execution_states')
              .select('status')
              .eq('set_id', fx.setId)
              .single();
          expect(esRow['status'], equals('completed'));
        },
      );

      test(
        'DOD-4: Auto-start — GPS inside origin zone transitions planned → inTransit; '
        'SYSTEM_AUTO_START audit row has actor_type=system',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          const serial = 'DEV-DOD4-AUTOSTART';
          final fx = await _seed(
            sc,
            orgId: orgId,
            status: 'planned',
            withOriginZone: true,
            withDestZone: false,
            deviceSerial: serial,
          );

          final r = await sc.rpc<Map<String, dynamic>>(
            'process_gps_for_execution_transitions',
            params: {
              'p_org_id': fx.orgId,
              'p_device_serial': serial,
              'p_lat': _inOrigLat,
              'p_lng': _inOrigLng,
            },
          );

          expect(r['result'], equals('started'));

          final esRow = await sc
              .from('execution_states')
              .select('status')
              .eq('set_id', fx.setId)
              .single();
          expect(esRow['status'], equals('inTransit'));

          // INV-3: SYSTEM_AUTO_START appended with system actor (C3).
          final audit = await sc
              .from('sla_audit_ledger')
              .select('actor_type, actor_id')
              .eq('set_id', fx.setId)
              .eq('type', 'SYSTEM_AUTO_START');

          expect(audit.length, equals(1));
          expect(audit.first['actor_type'], equals('system'));
          expect(audit.first['actor_id'], isNull);
        },
      );
    },
  );

  // ── Adversarial ─────────────────────────────────────────────────────────────

  group(
    'Autonomous Closer — Adversarial',
    skip: !isRunning ? 'Supabase not running locally' : null,
    () {
      late SupabaseClient sc;

      setUpAll(() {
        sc = PostgresTestConfig.createServiceRoleClient();
      });

      tearDownAll(() async {
        await sc.dispose();
      });

      test(
        'EDGE-1: GPS outside dest zone → outside_dest_zone; '
        'status unchanged, destination_zone_entered_at_utc stays NULL',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

          final r = await sc.rpc<Map<String, dynamic>>(
            'check_and_close_execution_autonomously',
            params: {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              'p_current_lat': _outDestLat,
              'p_current_lng': _outDestLng,
            },
          );

          expect(r['result'], equals('outside_dest_zone'));

          final esRow = await sc
              .from('execution_states')
              .select('status, destination_zone_entered_at_utc')
              .eq('set_id', fx.setId)
              .single();
          expect(esRow['status'], equals('inTransit'));
          expect(esRow['destination_zone_entered_at_utc'], isNull);
        },
      );

      test(
        'EDGE-2: Dwell 2 min (< 5 min threshold) → dwell_pending, no close',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

          await sc
              .from('execution_states')
              .update({
                'destination_zone_entered_at_utc': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(minutes: 2))
                    .toIso8601String(),
              })
              .eq('set_id', fx.setId)
              .eq('organization_id', fx.orgId);

          final r = await sc.rpc<Map<String, dynamic>>(
            'check_and_close_execution_autonomously',
            params: {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              'p_current_lat': _inDestLat,
              'p_current_lng': _inDestLng,
            },
          );

          expect(r['result'], equals('dwell_pending'));

          final esRow = await sc
              .from('execution_states')
              .select('status')
              .eq('set_id', fx.setId)
              .single();
          expect(esRow['status'], equals('inTransit'));
        },
      );

      test(
        'EDGE-3: Dwell boundary — 250 s → pending; 400 s → closed',
        () async {
          const uuid = Uuid();

          // Sub-case A: 250 s < 300 s threshold → dwell_pending.
          {
            final orgId = uuid.v4();
            final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

            await sc
                .from('execution_states')
                .update({
                  'destination_zone_entered_at_utc': DateTime.now()
                      .toUtc()
                      .subtract(const Duration(seconds: 250))
                      .toIso8601String(),
                })
                .eq('set_id', fx.setId)
                .eq('organization_id', fx.orgId);

            final r = await sc.rpc<Map<String, dynamic>>(
              'check_and_close_execution_autonomously',
              params: {
                'p_org_id': fx.orgId,
                'p_set_id': fx.setId,
                'p_current_lat': _inDestLat,
                'p_current_lng': _inDestLng,
              },
            );

            expect(
              r['result'],
              equals('dwell_pending'),
              reason: '250 s is below the 300 s gate',
            );
          }

          // Sub-case B: 400 s > 300 s threshold → closed.
          {
            final orgId = uuid.v4();
            final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

            await sc
                .from('execution_states')
                .update({
                  'destination_zone_entered_at_utc': DateTime.now()
                      .toUtc()
                      .subtract(const Duration(seconds: 400))
                      .toIso8601String(),
                })
                .eq('set_id', fx.setId)
                .eq('organization_id', fx.orgId);

            final r = await sc.rpc<Map<String, dynamic>>(
              'check_and_close_execution_autonomously',
              params: {
                'p_org_id': fx.orgId,
                'p_set_id': fx.setId,
                'p_current_lat': _inDestLat,
                'p_current_lng': _inDestLng,
              },
            );

            expect(
              r['result'],
              equals('closed'),
              reason: '400 s exceeds the 300 s gate',
            );
          }
        },
      );

      test(
        'EDGE-4: One of two required types missing → evidence_pending',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

          await _seedEvidenceRule(
            sc,
            orgId: fx.orgId,
            contractId: fx.contractId,
            types: ['lacre', 'carregamento'],
          );

          final driverId = await PostgresTestConfig.seedDriver(
            sc,
            orgId: fx.orgId,
          );
          // Only lacre — carregamento absent.
          await _seedEvidence(
            sc,
            orgId: fx.orgId,
            setId: fx.setId,
            driverId: driverId,
            category: 'lacre',
          );

          final r = await sc.rpc<Map<String, dynamic>>(
            'check_and_close_execution_autonomously',
            params: {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              'p_current_lat': _inDestLat,
              'p_current_lng': _inDestLng,
            },
          );

          expect(r['result'], equals('evidence_pending'));

          final esRow = await sc
              .from('execution_states')
              .select('status')
              .eq('set_id', fx.setId)
              .single();
          expect(esRow['status'], equals('inTransit'));
        },
      );

      test(
        'EDGE-5: CAS race — exactly one SYSTEM_AUTO_CLOSE audit row (INV-15)',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

          // Pre-backdate dwell so both concurrent calls see it ready.
          await sc
              .from('execution_states')
              .update({
                'destination_zone_entered_at_utc': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(minutes: 6))
                    .toIso8601String(),
              })
              .eq('set_id', fx.setId)
              .eq('organization_id', fx.orgId);

          final sc2 = PostgresTestConfig.createServiceRoleClient();
          try {
            final params = {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              'p_current_lat': _inDestLat,
              'p_current_lng': _inDestLng,
            };

            final results = await Future.wait([
              sc.rpc<dynamic>(
                'check_and_close_execution_autonomously',
                params: params,
              ),
              sc2.rpc<dynamic>(
                'check_and_close_execution_autonomously',
                params: params,
              ),
            ]);

            // Both report 'closed': winner closes, loser gets idempotent path.
            for (final r in results) {
              expect((r as Map<String, dynamic>)['result'], equals('closed'));
            }

            // INV-15: exactly one SYSTEM_AUTO_CLOSE row despite race.
            final auditRows = await sc
                .from('sla_audit_ledger')
                .select()
                .eq('set_id', fx.setId)
                .eq('type', 'SYSTEM_AUTO_CLOSE');

            expect(
              auditRows.length,
              equals(1),
              reason: 'CAS must prevent double-audit (INV-15)',
            );
          } finally {
            await sc2.dispose();
          }
        },
      );

      test(
        'EDGE-6: Wrong org → not_found; execution under correct org unchanged (INV-26)',
        () async {
          const uuid = Uuid();
          final orgA = uuid.v4();
          final orgB = uuid.v4();
          final fx = await _seed(sc, orgId: orgA, status: 'inTransit');
          await PostgresTestConfig.ensureSentinelOrg(id: orgB);

          final r = await sc.rpc<Map<String, dynamic>>(
            'check_and_close_execution_autonomously',
            params: {
              'p_org_id': orgB,
              'p_set_id': fx.setId,
              'p_current_lat': _inDestLat,
              'p_current_lng': _inDestLng,
            },
          );

          expect(
            r['result'],
            equals('not_found'),
            reason:
                'Wrong-org must be indistinguishable from not-found (INV-26)',
          );

          final esRow = await sc
              .from('execution_states')
              .select('status')
              .eq('set_id', fx.setId)
              .single();
          expect(esRow['status'], equals('inTransit'));
        },
      );

      test(
        'EDGE-7: No GPS params + no canonical_facts for vehicle → no_gps_data',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          // withDestZone = true so the function proceeds to GPS resolution.
          final fx = await _seed(
            sc,
            orgId: orgId,
            status: 'inTransit',
            withDestZone: true,
          );

          // Call without GPS params — function must try canonical_facts and fail.
          final r = await sc.rpc<Map<String, dynamic>>(
            'check_and_close_execution_autonomously',
            params: {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              // p_current_lat / p_current_lng intentionally omitted → DEFAULT NULL
            },
          );

          expect(r['result'], equals('no_gps_data'));
        },
      );

      test('EDGE-8: Unknown device_serial → no_asset', () async {
        const uuid = Uuid();
        final orgId = uuid.v4();
        await PostgresTestConfig.ensureSentinelOrg(id: orgId);

        final r = await sc.rpc<Map<String, dynamic>>(
          'process_gps_for_execution_transitions',
          params: {
            'p_org_id': orgId,
            'p_device_serial': 'UNKNOWN-DEV-${uuid.v4()}',
            'p_lat': _inOrigLat,
            'p_lng': _inOrigLng,
          },
        );

        expect(r['result'], equals('no_asset'));
      });

      test(
        'EDGE-9: Already completed → closed without new SYSTEM_AUTO_CLOSE audit row (INV-15)',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          final fx = await _seed(sc, orgId: orgId, status: 'inTransit');

          // Close directly — no audit row for this call.
          // RPC returns BOOLEAN (see 20260702000001_complete_execution_rpc.sql).
          await sc.rpc<bool>(
            'complete_execution',
            params: {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              'p_reason': 'TEST_DIRECT_CLOSE',
            },
          );

          final auditBefore =
              (await sc
                      .from('sla_audit_ledger')
                      .select()
                      .eq('set_id', fx.setId)
                      .eq('type', 'SYSTEM_AUTO_CLOSE'))
                  .length;

          // Autonomous closer on already-completed execution.
          final r = await sc.rpc<Map<String, dynamic>>(
            'check_and_close_execution_autonomously',
            params: {
              'p_org_id': fx.orgId,
              'p_set_id': fx.setId,
              'p_current_lat': _inDestLat,
              'p_current_lng': _inDestLng,
            },
          );

          expect(r['result'], equals('closed'));

          final auditAfter =
              (await sc
                      .from('sla_audit_ledger')
                      .select()
                      .eq('set_id', fx.setId)
                      .eq('type', 'SYSTEM_AUTO_CLOSE'))
                  .length;

          expect(
            auditAfter,
            equals(auditBefore),
            reason:
                'Terminal-state early-return must not append a duplicate audit row',
          );
        },
      );

      test(
        'EDGE-10: Planned execution with no origin zone → none, status unchanged',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          const serial = 'DEV-EDGE10-NO-ZONE';
          final fx = await _seed(
            sc,
            orgId: orgId,
            status: 'planned',
            withOriginZone: false,
            withDestZone: false,
            deviceSerial: serial,
          );

          final r = await sc.rpc<Map<String, dynamic>>(
            'process_gps_for_execution_transitions',
            params: {
              'p_org_id': fx.orgId,
              'p_device_serial': serial,
              'p_lat': _inOrigLat,
              'p_lng': _inOrigLng,
            },
          );

          expect(r['result'], equals('none'));

          final esRow = await sc
              .from('execution_states')
              .select('status')
              .eq('set_id', fx.setId)
              .single();
          expect(esRow['status'], equals('planned'));
        },
      );
    },
  );

  // ── INV-6 Denial — ingest-sascar Edge Function ───────────────────────────────

  group(
    'INV-6 Denial — ingest-sascar (C4)',
    skip: !isFnRunning ? 'Edge Functions not running locally' : null,
    () {
      late SupabaseClient sc;

      setUpAll(() {
        sc = PostgresTestConfig.createServiceRoleClient();
      });

      tearDownAll(() async {
        await sc.dispose();
      });

      test(
        'EDGE-11: Missing event_time → HTTP 422, ingestion_alerts row inserted, '
        'canonical_facts NOT created',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          await PostgresTestConfig.ensureSentinelOrg(id: orgId);
          final rawKey = await _seedSascarKey(sc, orgId);

          final resp = await http.post(
            Uri.parse(
              '${PostgresTestConfig.supabaseUrl}/functions/v1/ingest-sascar',
            ),
            headers: {
              'Authorization': 'Bearer $rawKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'device_serial': 'DEV-EDGE11-${orgId.substring(0, 8)}',
              // event_time intentionally absent — INV-6 denial.
              'latitude': _inDestLat,
              'longitude': _inDestLng,
              'speed_kmh': 60.0,
            }),
          );

          expect(resp.statusCode, equals(422));

          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          expect(body['status'], equals('rejected'));
          expect(body['reason'], equals('missing_event_time'));

          // ingestion_alerts row must be present (INV-10).
          final alerts = await sc
              .from('ingestion_alerts')
              .select('alert_type, detail')
              .eq('organization_id', orgId);

          expect(alerts.length, equals(1));
          expect(
            alerts.first['alert_type'],
            equals('INGESTION_INTEGRITY_ERROR'),
          );

          // No canonical_facts created.
          final facts = await sc
              .from('canonical_facts')
              .select()
              .eq('organization_id', orgId);
          expect(facts, isEmpty);
        },
      );

      test(
        'EDGE-12: Two calls with missing event_time → two distinct alert rows '
        '(each absent ping is a separate event; idempotency NOT required for alerts)',
        () async {
          const uuid = Uuid();
          final orgId = uuid.v4();
          await PostgresTestConfig.ensureSentinelOrg(id: orgId);
          final rawKey = await _seedSascarKey(sc, orgId);
          const serial = 'DEV-EDGE12';

          for (var i = 0; i < 2; i++) {
            await http.post(
              Uri.parse(
                '${PostgresTestConfig.supabaseUrl}/functions/v1/ingest-sascar',
              ),
              headers: {
                'Authorization': 'Bearer $rawKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'device_serial': serial,
                // event_time absent on both calls.
                'latitude': _inDestLat,
                'longitude': _inDestLng,
                'speed_kmh': 60.0,
              }),
            );
          }

          final alerts = await sc
              .from('ingestion_alerts')
              .select()
              .eq('organization_id', orgId);

          expect(
            alerts.length,
            equals(2),
            reason: 'Two absent pings must produce two distinct alert rows',
          );
        },
      );
    },
  );
}
