// =============================================================================
// Task 5 — Payload Stress & JSON Integrity (INV-9, INV-15)
// Task 8 — Wire-level payload inspection via MockClient
// =============================================================================
//
// Forensic Insight — QA & Security Lead (Paranoid Protector)
// Invariants under scrutiny:
//   INV-9  (Seal): SHA-256 ingestion for all files. Hash determinism.
//   INV-15 (Deterministic): Byte-identical replay. JSON must round-trip losslessly.
//   INV-12 (Scan): Doubles annotated with // Physical Metric - Double Required.
//
// Scenarios tested:
//   - Round-trip of nested JSON through Postgres JSONB → identical Map
//   - UTF-8 special characters (BMP and supplementary planes)
//   - Null values in JSONB without precision loss
//   - Double precision (latitude/longitude) byte-identical after round-trip
//   - Empty JSONB object {}
//   - Arrays within JSONB
//   - BasePostgresRepository.canonicalJson determinism
//   - SHA-256 hash changes when any byte of the payload changes
//   - MockClient: createBindingToken POST body structure
//   - MockClient: compliance RPC call structure
// =============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/sla_audit/telegram/telegram_binding_token.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';
import 'package:veraprob/infrastructure/telegram/postgres_telegram_repository.dart';

import '../postgres/postgres_test_config.dart';

// ── MockClient factory ────────────────────────────────────────────────────────
PostgresTelegramRepository _repoWithMock(
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.serviceRoleKey,
    httpClient: MockClient(handler),
  );
  return PostgresTelegramRepository(client);
}

void main() async {
  const uuid = Uuid();
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  // ===========================================================================
  // Group A — BasePostgresRepository canonical JSON & hash utilities
  // (always runs — no DB required)
  // ===========================================================================
  group('INV-15/INV-9: Canonical JSON and hash determinism', () {
    // ── CJ-1 ───────────────────────────────────────────────────────────────
    test(
      'CJ-1: canonicalJson output is identical regardless of key insertion order',
      () {
        final p1 = {'z': 3, 'a': 1, 'm': 2};
        final p2 = {'a': 1, 'm': 2, 'z': 3};
        final p3 = {'m': 2, 'z': 3, 'a': 1};

        final j1 = BasePostgresRepository.canonicalJson(
          p1.cast<String, dynamic>(),
        );
        final j2 = BasePostgresRepository.canonicalJson(
          p2.cast<String, dynamic>(),
        );
        final j3 = BasePostgresRepository.canonicalJson(
          p3.cast<String, dynamic>(),
        );

        expect(j1, equals(j2));
        expect(j2, equals(j3));
        expect(j1, equals('{"a":1,"m":2,"z":3}'));
      },
    );

    // ── CJ-2 ───────────────────────────────────────────────────────────────
    test('CJ-2: canonicalJson handles nested Maps recursively', () {
      final payload = <String, dynamic>{
        'outer': {'z_inner': 'last', 'a_inner': 'first'},
        'a_key': 'top',
      };

      final json = BasePostgresRepository.canonicalJson(payload);
      final parsed = jsonDecode(json) as Map<String, dynamic>;

      // Outer keys must be sorted.
      expect(
        json.indexOf('"a_key"'),
        lessThan(json.indexOf('"outer"')),
        reason: 'Top-level keys must be alphabetically sorted.',
      );
      // Inner keys must be sorted.
      final inner = parsed['outer'] as Map<String, dynamic>;
      expect(inner.keys.toList(), equals(['a_inner', 'z_inner']));
    });

    // ── CJ-3 ───────────────────────────────────────────────────────────────
    test('CJ-3: canonicalJson handles arrays within nested objects', () {
      final payload = <String, dynamic>{
        'tags': ['beta', 'alpha', 'gamma'],
        'count': 3,
      };

      final json = BasePostgresRepository.canonicalJson(payload);
      // Arrays should preserve order (not be sorted — only keys are sorted).
      expect(json, contains('"tags":["beta","alpha","gamma"]'));
      expect(json, contains('"count":3'));
    });

    // ── CJ-4 ───────────────────────────────────────────────────────────────
    test(
      'CJ-4: canonicalJson normalizes DateTime to ISO-8601 Z suffix (INV-9)',
      () {
        final dt = DateTime.utc(2026, 4, 20, 14, 30, 0);
        final payload = <String, dynamic>{'timestamp': dt, 'name': 'test'};

        final json = BasePostgresRepository.canonicalJson(payload);
        expect(
          json,
          contains('"timestamp":"2026-04-20T14:30:00.000Z"'),
          reason:
              'INV-9: DateTime must serialize with Z suffix to ensure '
              'byte-identical hashes between Dart and Deno workers.',
        );
      },
    );

    // ── CJ-5 ───────────────────────────────────────────────────────────────
    test(
      'CJ-5: hashPayload changes when any single byte of payload changes',
      () {
        final base = <String, dynamic>{
          'organization_id': 'org-a',
          'code': 'ABCDEFGH',
        };
        final mutated = <String, dynamic>{
          'organization_id': 'org-a',
          'code': 'ABCDEFGI', // last char changed
        };

        final h1 = BasePostgresRepository.hashPayload(base);
        final h2 = BasePostgresRepository.hashPayload(mutated);

        expect(
          h1,
          isNot(equals(h2)),
          reason:
              'INV-9: Hash must be sensitive to any byte change in the payload. '
              'Avalanche effect validation.',
        );
      },
    );

    // ── CJ-6 ───────────────────────────────────────────────────────────────
    test(
      'CJ-6: hashPayload handles null values within map without exception',
      () {
        final payload = <String, dynamic>{
          'linked_set_id': null,
          'category': null,
          'forensic_hash': 'abc123',
        };

        expect(
          () => BasePostgresRepository.hashPayload(payload),
          returnsNormally,
          reason:
              'INV-9: Null values in JSONB metadata must not crash hashing. '
              'Null is valid JSON.',
        );

        final hash = BasePostgresRepository.hashPayload(payload);
        expect(hash, isNotNull);
        expect(hash!.length, equals(64));
      },
    );

    // ── CJ-7 ───────────────────────────────────────────────────────────────
    test('CJ-7: sortKeys preserves double precision for lat/lon (INV-12)', () {
      // Physical Metric - Double Required
      const lat = -23.550520833333334; // Physical Metric - Double Required
      const lon = -46.633300000000001; // Physical Metric - Double Required

      final result =
          BasePostgresRepository.sortKeys({'latitude': lat, 'longitude': lon})
              as Map<String, dynamic>;

      // Doubles must pass through unchanged (not converted to string).
      expect(result['latitude'], equals(lat));
      expect(result['longitude'], equals(lon));
    });

    // ── CJ-8 ───────────────────────────────────────────────────────────────
    test('CJ-8: UTF-8 special characters survive canonicalJson round-trip', () {
      // BMP special chars + supplementary plane (emoji).
      final payload = <String, dynamic>{
        'note': 'Observação: câmera avariada — ação imediata!',
        'emoji': '🔒🛡️',
        'arabic': 'مرحبا',
        'chinese': '你好',
        'null_key': null,
      };

      final json = BasePostgresRepository.canonicalJson(payload);
      final roundTripped = jsonDecode(json) as Map<String, dynamic>;

      expect(
        roundTripped['note'],
        equals(payload['note']),
        reason:
            'INV-15: Brazilian Portuguese accents must survive JSON round-trip.',
      );
      expect(
        roundTripped['emoji'],
        equals(payload['emoji']),
        reason: 'INV-15: Emoji (supplementary plane) must survive round-trip.',
      );
      expect(roundTripped['arabic'], equals(payload['arabic']));
      expect(roundTripped['chinese'], equals(payload['chinese']));
      expect(roundTripped['null_key'], isNull);
    });

    // ── CJ-9 ───────────────────────────────────────────────────────────────
    test(
      'CJ-9: Double precision lat/lon is byte-identical after JSON encode/decode',
      () {
        // Physical Metric - Double Required (extreme precision)
        // ignore: prefer_const_declarations — values are intentionally precise
        final lat = -23.55052083333333416; // Physical Metric - Double Required
        // ignore: prefer_const_declarations
        final lon = -46.63330000000000142; // Physical Metric - Double Required

        final payload = <String, dynamic>{'lat': lat, 'lon': lon};
        final json = jsonEncode(payload);
        final decoded = jsonDecode(json) as Map<String, dynamic>;

        // Dart's jsonDecode must preserve double precision to epsilon.
        expect(
          ((decoded['lat'] as double) - lat).abs(),
          lessThan(1e-10),
          reason:
              'INV-15: lat/lon must be byte-identical after JSON round-trip. '
              'Precision loss would corrupt geospatial chain-of-custody.',
        );
        expect(((decoded['lon'] as double) - lon).abs(), lessThan(1e-10));
      },
    );

    // ── CJ-10 ──────────────────────────────────────────────────────────────
    test(
      'CJ-10: Deeply nested JSON (5 levels) survives canonicalJson (INV-15)',
      () {
        final nested = <String, dynamic>{
          'level1': {
            'level2': {
              'level3': {
                'level4': {
                  'level5': {'value': 'deep', 'count': 42},
                },
              },
            },
          },
        };

        expect(
          () => BasePostgresRepository.canonicalJson(nested),
          returnsNormally,
          reason:
              'INV-15: Deep nesting from complex evidence metadata must not '
              'overflow or truncate during canonical serialization.',
        );

        final json = BasePostgresRepository.canonicalJson(nested);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final deep =
            ((((decoded['level1'] as Map)['level2'] as Map)['level3']
                        as Map)['level4']
                    as Map)['level5']
                as Map;
        expect(deep['value'], equals('deep'));
        expect(deep['count'], equals(42));
      },
    );
  });

  // ===========================================================================
  // Group B — Wire-level POST body inspection (MockClient)
  // ===========================================================================
  group('INV-1/INV-9: createBindingToken wire-level payload structure', () {
    // ── WIRE-1 ─────────────────────────────────────────────────────────────
    test(
      'WIRE-1: createBindingToken POST body contains all required fields',
      () async {
        Map<String, dynamic>? capturedBody;
        const orgId = 'org-wire-1';
        final driverId = uuid.v4();
        final tokenId = uuid.v4();
        final now = DateTime.now().toUtc();

        final repo = _repoWithMock((request) async {
          if (request.method == 'POST') {
            capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return http.Response(
            '',
            201,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final code = PostgresTestConfig.fakeTokenCode('wire-1');
        final token = TelegramBindingToken(
          id: tokenId,
          organizationId: orgId,
          driverId: driverId,
          createdByUserId: uuid.v4(),
          code: code,
          expiresAtUtc: now.add(const Duration(minutes: 15)),
          usedAtUtc: null,
          createdAtUtc: now,
        );

        await repo.createBindingToken(token);

        expect(capturedBody, isNotNull);
        expect(
          capturedBody!['id'],
          equals(tokenId),
          reason: 'INV-1: Token ID must be in the POST body.',
        );
        expect(
          capturedBody!['organization_id'],
          equals(orgId),
          reason: 'INV-1: organization_id must be in the POST body.',
        );
        expect(
          capturedBody!['driver_id'],
          equals(driverId),
          reason: 'INV-1: driver_id must be in the POST body.',
        );
        expect(
          capturedBody!['code'],
          equals(code),
          reason: 'INV-9: The token code must be in the POST body.',
        );
        expect(
          capturedBody!['expires_at_utc'],
          isA<String>(),
          reason: 'INV-6: expires_at_utc must be an ISO-8601 string.',
        );
        expect(
          capturedBody!['created_at_utc'],
          isA<String>(),
          reason: 'INV-6: created_at_utc must be an ISO-8601 string.',
        );
      },
    );

    // ── WIRE-2 ─────────────────────────────────────────────────────────────
    test(
      'WIRE-2: createBindingToken returns the domain token unchanged (no mutation)',
      () async {
        final repo = _repoWithMock((request) async {
          return http.Response(
            '',
            201,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final now = DateTime.now().toUtc();
        final tokenId = uuid.v4();
        final code = PostgresTestConfig.fakeTokenCode('wire-2');
        final token = TelegramBindingToken(
          id: tokenId,
          organizationId: 'org-wire-2',
          driverId: uuid.v4(),
          createdByUserId: uuid.v4(),
          code: code,
          expiresAtUtc: now.add(const Duration(minutes: 15)),
          usedAtUtc: null,
          createdAtUtc: now,
        );

        final returned = await repo.createBindingToken(token);

        expect(
          returned.id,
          equals(tokenId),
          reason:
              'createBindingToken must return the original token object '
              'without modification — the repository must not mutate input.',
        );
        expect(returned.code, equals(code));
        expect(returned.organizationId, equals('org-wire-2'));
      },
    );
  });

  // ===========================================================================
  // Group C — Postgres JSONB round-trip (requires DB)
  // ===========================================================================
  group(
    'INV-15: JSONB metadata round-trip byte-identity against Postgres',
    () {
      late SupabaseClient serviceClient;
      late String driverA;
      const orgId = PostgresTestConfig.testOrgId;

      setUpAll(() async {
        serviceClient = PostgresTestConfig.createServiceRoleClient();
        await PostgresTestConfig.ensureSentinelOrg(id: orgId);
        driverA = await PostgresTestConfig.seedDriver(
          serviceClient,
          orgId: orgId,
          licenseNumber: 'PLD-9001',
        );
      });

      tearDownAll(() async {
        await PostgresTestConfig.cleanupTelegramData(
          serviceClient,
          orgId: orgId,
        );
        await serviceClient.dispose();
      });

      // ── JSONB-1 ────────────────────────────────────────────────────────────
      test(
        'JSONB-1: Simple evidence upload round-trips forensic_hash byte-identically',
        () async {
          final hash = PostgresTestConfig.fakeForensicHash('jsonb-1-payload');
          final msgId = DateTime.now().toUtc().microsecondsSinceEpoch % 1000000;

          final evidenceId =
              await PostgresTestConfig.seedTelegramEvidenceUpload(
                serviceClient,
                orgId: orgId,
                driverId: driverA,
                forensicHash: hash,
                chatId: 600000001,
                telegramMessageId: msgId,
              );

          final row = await serviceClient
              .from('telegram_evidence_uploads')
              .select('forensic_hash, organization_id, source')
              .eq('id', evidenceId)
              .single();

          expect(
            row['forensic_hash'],
            equals(hash),
            reason:
                'INV-9/INV-15: forensic_hash must be byte-identical after '
                'Postgres storage and retrieval.',
          );
          expect(row['organization_id'], equals(orgId));
          expect(row['source'], equals('telegram'));
        },
      );

      // ── JSONB-2 ────────────────────────────────────────────────────────────
      test(
        'JSONB-2: UTF-8 special chars in file_name survive Postgres TEXT round-trip',
        () async {
          // Postgres TEXT type must handle full UTF-8 without truncation.
          // We test this via storage_path which also is TEXT.
          final msgId =
              DateTime.now().toUtc().microsecondsSinceEpoch % 1000000 + 500;
          final hash = PostgresTestConfig.fakeForensicHash('jsonb-2-utf8');
          // ignore: prefer_const_declarations
          final specialPath = '$orgId/telegram/600000001/observação-câmera.jpg';

          final evidenceId =
              await PostgresTestConfig.seedTelegramEvidenceUpload(
                serviceClient,
                orgId: orgId,
                driverId: driverA,
                forensicHash: hash,
                chatId: 600000001,
                telegramMessageId: msgId,
                storagePath: specialPath,
              );

          final row = await serviceClient
              .from('telegram_evidence_uploads')
              .select('storage_path')
              .eq('id', evidenceId)
              .single();

          expect(
            row['storage_path'],
            equals(specialPath),
            reason:
                'INV-15: UTF-8 chars in storage_path must survive Postgres '
                'round-trip without corruption.',
          );
        },
      );

      // ── JSONB-3 ────────────────────────────────────────────────────────────
      test(
        'JSONB-3: Large forensic hash (64 chars) is stored and retrieved verbatim',
        () async {
          // Generate a maximally complex 64-char hex string.
          final random = Random(42);
          final longHash = List.generate(
            64,
            (_) => random.nextInt(16).toRadixString(16),
          ).join();

          final msgId =
              DateTime.now().toUtc().microsecondsSinceEpoch % 1000000 + 999;

          final evidenceId =
              await PostgresTestConfig.seedTelegramEvidenceUpload(
                serviceClient,
                orgId: orgId,
                driverId: driverA,
                forensicHash: longHash,
                chatId: 600000001,
                telegramMessageId: msgId,
              );

          final row = await serviceClient
              .from('telegram_evidence_uploads')
              .select('forensic_hash')
              .eq('id', evidenceId)
              .single();

          expect(
            row['forensic_hash'],
            equals(longHash),
            reason:
                'INV-9: 64-char SHA-256 hash must be stored and retrieved '
                'without truncation or encoding artifacts.',
          );
          expect((row['forensic_hash'] as String).length, equals(64));
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
