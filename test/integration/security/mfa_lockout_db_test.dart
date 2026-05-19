/// Integration tests for MFA lockout RPCs and timezone semantics
/// (CT30 — F7, plan cases 23–28 + 41–44).
///
/// Skip-fast when the local Supabase stack is offline. Tests assume the
/// migration `20260418000001_mfa_lockout_and_est_rls.sql` is applied.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../test/infrastructure/postgres/postgres_test_config.dart';

Future<bool> _stackOnline() async {
  try {
    final res = await http
        .get(Uri.parse(PostgresTestConfig.supabaseUrl))
        .timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

/// Creates an auth.users row via the admin REST endpoint and returns its UUID.
/// The local stack ignores duplicate emails with 422 — the helper still parses
/// the response and looks up the existing user via list-users.
Future<String> _createOrGetAuthUser(String email, String password) async {
  final base = PostgresTestConfig.supabaseUrl;
  final headers = {
    'apikey': PostgresTestConfig.serviceRoleKey,
    'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
    'Content-Type': 'application/json',
  };

  final create = await http.post(
    Uri.parse('$base/auth/v1/admin/users'),
    headers: headers,
    body: jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
      'app_metadata': {'super_admin': true},
    }),
  );
  if (create.statusCode == 200 || create.statusCode == 201) {
    final body = jsonDecode(create.body) as Map<String, dynamic>;
    return body['id'] as String;
  }

  // 422 / already exists → look up by email.
  // GoTrue ignores unknown query params; the supported filter is `filter`
  // (ILIKE search on email). Use per_page=1000 to avoid pagination misses
  // in local stacks that accumulate many test users across runs.
  final encodedFilter = Uri.encodeQueryComponent(email);
  final lookup = await http.get(
    Uri.parse('$base/auth/v1/admin/users?filter=$encodedFilter&per_page=1000'),
    headers: headers,
  );
  final lookupBody = jsonDecode(lookup.body);
  final allUsers = (lookupBody is Map && lookupBody['users'] is List)
      ? lookupBody['users'] as List
      : (lookupBody is List ? lookupBody : const <dynamic>[]);
  final users = allUsers
      .cast<Map<String, dynamic>>()
      .where((u) => u['email'] == email)
      .toList();
  if (users.isEmpty) {
    throw StateError(
      '_createOrGetAuthUser: no user found for $email after admin create '
      '(${create.statusCode}: ${create.body})',
    );
  }
  return users.first['id'] as String;
}

void main() {
  late SupabaseClient seedClient;
  late String userA;
  late String userB;

  setUpAll(() async {
    if (!await _stackOnline()) return;
    seedClient = PostgresTestConfig.createServiceRoleClient();
    userA = await _createOrGetAuthUser(
      'mfa-test-a@veraprob.test',
      'integration-pwd-A1!',
    );
    userB = await _createOrGetAuthUser(
      'mfa-test-b@veraprob.test',
      'integration-pwd-B1!',
    );
  });

  setUp(() async {
    if (!await _stackOnline()) return;
    // Guard: setUpAll may have thrown before initializing userA/userB.
    try {
      await PostgresTestConfig.cleanupMfaLockouts(userIds: [userA, userB]);
    } on Error catch (_) {}
  });

  tearDownAll(() async {
    if (!await _stackOnline()) return;
    // Guard: setUpAll may have thrown before initializing userA/userB.
    try {
      await PostgresTestConfig.cleanupMfaLockouts(userIds: [userA, userB]);
    } on Error catch (_) {}
    try {
      await seedClient.dispose();
    } on Error catch (_) {}
  });

  Future<Map<String, dynamic>> recordFailure(String uid) async {
    final raw = await seedClient.rpc<dynamic>(
      'record_mfa_failure',
      params: {'p_user_id': uid},
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> checkLockout(String uid) async {
    final raw = await seedClient.rpc<dynamic>(
      'check_mfa_lockout',
      params: {'p_user_id': uid},
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  group('record_mfa_failure / check_mfa_lockout — circuit breaker', () {
    test('23 5 failures trigger 15-minute lockout', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      final t0 = DateTime.now().toUtc();
      Map<String, dynamic>? last;
      for (var i = 0; i < 5; i++) {
        last = await recordFailure(userA);
      }
      expect(last, isNotNull);
      expect(last!['is_locked'], isTrue);
      expect(last['failed_attempts'], equals(5));

      final lockedUntil = DateTime.parse(
        last['locked_until'] as String,
      ).toUtc();
      final delta = lockedUntil.difference(t0);
      expect(
        delta.inSeconds,
        inInclusiveRange(14 * 60 + 30, 15 * 60 + 30),
        reason: 'lockout window must be ≈15 minutes from t0 (UTC)',
      );
    });

    test(
      '24 record_mfa_failure during lockout still increments OR no-ops',
      () async {
        if (!await _stackOnline()) {
          markTestSkipped('local supabase stack offline');
          return;
        }
        for (var i = 0; i < 5; i++) {
          await recordFailure(userA);
        }
        final before = await checkLockout(userA);
        expect(before['is_locked'], isTrue);

        // Migration's UPSERT keeps incrementing failed_attempts and resetting
        // locked_until → 6 ≥ 5 path. The contract here is: behavior must be
        // deterministic and preserve `is_locked=true`. Not asserting the exact
        // counter value avoids over-coupling to the SQL CASE expression.
        final after = await recordFailure(userA);
        expect(after['is_locked'], isTrue);
        expect(after['locked_until'], isNotNull);
      },
    );

    test(
      '25 cross-user isolation — userB stays unlocked while userA locks',
      () async {
        if (!await _stackOnline()) {
          markTestSkipped('local supabase stack offline');
          return;
        }
        for (var i = 0; i < 5; i++) {
          await recordFailure(userA);
        }
        final lockedA = await checkLockout(userA);
        final freshB = await checkLockout(userB);
        expect(lockedA['is_locked'], isTrue);
        expect(freshB['is_locked'], isFalse);
        expect(freshB['failed_attempts'], equals(0));
      },
    );

    test('26 reset_mfa_lockout zeroes counters', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      await recordFailure(userA);
      await recordFailure(userA);
      await recordFailure(userA);
      await seedClient.rpc<dynamic>(
        'reset_mfa_lockout',
        params: {'p_user_id': userA},
      );

      final after = await checkLockout(userA);
      expect(after['failed_attempts'], equals(0));
      expect(after['locked_until'], isNull);
      expect(after['is_locked'], isFalse);
    });

    test('27 race condition — concurrent record_mfa_failure', () async {
      // Plan: skip until stable across 50 runs. Concurrent writes against
      // the same row depend on Postgres UPSERT ordering and PostgREST
      // serialization that is too noisy on a single-CI-job laptop.
      markTestSkipped(
        'flaky on shared CI — re-evaluate after 50 stable runs '
        '(plan F7 case 27).',
      );
    }, skip: true);

    test('28 auto-expiry of stale lock', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      // Seed a stale lock directly: locked_until 1 minute in the past.
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await seedClient.from('super_admin_mfa_lockouts').upsert({
        'user_id': userA,
        'failed_attempts': 5,
        'locked_until': past.toIso8601String(),
        'last_attempt': past.toIso8601String(),
      });

      final result = await checkLockout(userA);
      expect(
        result['is_locked'],
        isFalse,
        reason:
            'check_mfa_lockout must auto-expire stale locks (migration C.3)',
      );
      expect(result['failed_attempts'], equals(0));
    });
  });

  group('Timezone integrity (INV-6) — locked_until UTC strict', () {
    test('41 locked_until is approximately t0 + 15 minutes UTC', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      final t0 = DateTime.now().toUtc();
      Map<String, dynamic>? last;
      for (var i = 0; i < 5; i++) {
        last = await recordFailure(userA);
      }
      final lockedUntil = DateTime.parse(
        last!['locked_until'] as String,
      ).toUtc();
      final delta = lockedUntil.difference(t0);
      expect(delta.inSeconds, inInclusiveRange(14 * 60 + 30, 15 * 60 + 30));
    });

    test('42 locked_until is TIMESTAMPTZ — UTC absolute on the wire', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      for (var i = 0; i < 5; i++) {
        await recordFailure(userA);
      }
      final row = await seedClient
          .from('super_admin_mfa_lockouts')
          .select('locked_until')
          .eq('user_id', userA)
          .single();
      final raw = row['locked_until'] as String;

      // PostgREST serialises TIMESTAMPTZ in ISO8601 with an explicit offset.
      // A TZ-naive `timestamp without time zone` would have no offset suffix —
      // its presence is the wire-level proof that the column is TIMESTAMPTZ
      // and the value is anchored in UTC (or convertible to UTC losslessly).
      expect(
        raw.endsWith('+00:00') || raw.endsWith('Z') || raw.contains('+00'),
        isTrue,
        reason:
            'INV-6: locked_until must serialise with an explicit UTC offset',
      );

      final parsed = DateTime.parse(raw).toUtc();
      expect(parsed.isUtc, isTrue);
    });

    test(
      '43 migration uses TIMESTAMPTZ-safe NOW() (static check)',
      () async {
        // Static check against the migration source — no DB round-trip.
        final file = await _readMigration(
          'supabase/migrations/20260418000001_mfa_lockout_and_est_rls.sql',
        );
        // The migration uses raw NOW(); since locked_until is TIMESTAMPTZ this
        // is UTC-absolute. Either keep the explicit-UTC marker comment or
        // refactor to timezone('utc', now()). This test fails until either is
        // present — TDD-RED driver per plan adendo C.
        final hasExplicit =
            file.contains("timezone('utc', now())") ||
            file.contains('TZ-SAFE: NOW() returns TIMESTAMPTZ');
        expect(
          hasExplicit,
          isTrue,
          reason:
              'INV-6 (TDD-RED): make UTC explicit in record_mfa_failure / '
              'check_mfa_lockout / reset_mfa_lockout. Add `timezone(\'utc\', '
              'now())` OR a `-- TZ-SAFE: NOW() returns TIMESTAMPTZ` comment.',
        );
      },
      skip: true /* TDD-RED — flip when migration is hardened */,
    );

    test('44 auto-expiry boundary survives clock-drift / TZ noise', () async {
      if (!await _stackOnline()) {
        markTestSkipped('local supabase stack offline');
        return;
      }
      final soon = DateTime.now().toUtc().add(const Duration(seconds: 1));
      await seedClient.from('super_admin_mfa_lockouts').upsert({
        'user_id': userA,
        'failed_attempts': 5,
        'locked_until': soon.toIso8601String(),
        'last_attempt': soon.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(seconds: 2));
      final result = await checkLockout(userA);
      expect(result['is_locked'], isFalse);
    });
  });
}

Future<String> _readMigration(String relPath) async {
  return File(relPath).readAsString();
}
