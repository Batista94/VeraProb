// =============================================================================
// Task 2 — Forensic Immutability (INV-7 Violation Guard)
// Task 6 — Binding Token Immutability (INV-7, INV-9 — additional)
// =============================================================================
//
// Forensic Insight — QA & Security Lead (Paranoid Protector)
// Invariants under scrutiny:
//   INV-7  (Type/Immutability): No dynamic. Strict null safety.
//          Here interpreted as: evidence records are APPEND-ONLY.
//          Triggers: trg_teu_no_update, trg_teu_no_delete,
//                   trg_tbt_no_immutable_update, trg_tbt_no_delete
//   INV-9  (Seal): SHA-256 must never change after INSERT
//   INV-10 (Error): IntegrityException — no silent fail
//
// Attack scenarios:
//   - Attempt UPDATE on telegram_evidence_uploads (fully immutable).
//   - Attempt DELETE on telegram_evidence_uploads.
//   - Attempt UPDATE of immutable fields on telegram_binding_tokens.
//   - Attempt DELETE on telegram_binding_tokens.
//
// The triggers raise SQLSTATE 'restrict_violation' (23001).
// The repository's error interceptor must surface this as IntegrityException
// (via the P0001 / catch-all path), never as a raw PostgrestException.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

import '../postgres/postgres_test_config.dart';

// ── Helper mixin to access error mapping directly ────────────────────────────

/// Thin wrapper that exposes mapPostgrestToDomainException for direct testing.
class _ErrorMapper with PostgresErrorInterceptor {}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  // ===========================================================================
  // Group A — telegram_evidence_uploads immutability (trg_teu_no_update / delete)
  // ===========================================================================
  group(
    'INV-7: telegram_evidence_uploads is fully immutable',
    () {
      late SupabaseClient serviceClient;
      late String driverA;
      late String evidenceId;

      const orgA = PostgresTestConfig.testOrgId;

      setUpAll(() async {
        serviceClient = PostgresTestConfig.createServiceRoleClient();
        await PostgresTestConfig.ensureSentinelOrg(id: orgA);
        driverA = await PostgresTestConfig.seedDriver(
          serviceClient,
          orgId: orgA,
          licenseNumber: 'IMM-1001',
        );
      });

      setUp(() async {
        // Fresh unique message_id per test to avoid UNIQUE constraint conflict.
        final msgId = DateTime.now().toUtc().microsecondsSinceEpoch;
        final hash = PostgresTestConfig.fakeForensicHash('immutable-$msgId');
        evidenceId = await PostgresTestConfig.seedTelegramEvidenceUpload(
          serviceClient,
          orgId: orgA,
          driverId: driverA,
          forensicHash: hash,
          chatId: 300000001,
          telegramMessageId: msgId,
        );
      });

      tearDownAll(() async {
        await PostgresTestConfig.cleanupTelegramData(
          serviceClient,
          orgId: orgA,
        );
        await serviceClient.dispose();
      });

      // ── IMM-1 ──────────────────────────────────────────────────────────────
      test(
        'IMM-1: UPDATE on storage_path raises restrict_violation trigger',
        () async {
          // Attempt to UPDATE any field — trigger fires before the write.
          expect(
            () async {
              await serviceClient
                  .from('telegram_evidence_uploads')
                  .update({'storage_path': '/tampered/path.jpg'})
                  .eq('id', evidenceId);
            },
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.code,
                'code',
                anyOf(
                  equals('23001'), // restrict_violation (SQLSTATE)
                  equals('P0001'), // RAISE EXCEPTION maps to P0001
                  equals('42501'), // in case of service_role bypass attempt
                ),
              ),
            ),
            reason:
                'INV-7: trg_teu_no_update must fire and block any UPDATE '
                'on telegram_evidence_uploads. storage_path is immutable.',
          );
        },
      );

      // ── IMM-2 ──────────────────────────────────────────────────────────────
      test(
        'IMM-2: UPDATE on forensic_hash (INV-9) raises restrict_violation',
        () async {
          final tamperHash = PostgresTestConfig.fakeForensicHash(
            'tampered-hash',
          );
          expect(
            () async {
              await serviceClient
                  .from('telegram_evidence_uploads')
                  .update({'forensic_hash': tamperHash})
                  .eq('id', evidenceId);
            },
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.code,
                'code',
                anyOf(equals('23001'), equals('P0001'), equals('42501')),
              ),
            ),
            reason:
                'INV-9: forensic_hash is the chain-of-custody seal. '
                'trg_teu_no_update must block any modification after INSERT.',
          );
        },
      );

      // ── IMM-3 ──────────────────────────────────────────────────────────────
      test(
        'IMM-3: DELETE on telegram_evidence_uploads raises restrict_violation',
        () async {
          expect(
            () async {
              await serviceClient
                  .from('telegram_evidence_uploads')
                  .delete()
                  .eq('id', evidenceId);
            },
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.code,
                'code',
                anyOf(equals('23001'), equals('P0001'), equals('42501')),
              ),
            ),
            reason:
                'INV-7: trg_teu_no_delete must fire. '
                'Evidence records are append-only — DELETE is always blocked.',
          );
        },
      );

      // ── IMM-4 ──────────────────────────────────────────────────────────────
      test(
        'IMM-4: Repository propagates immutability error as IntegrityException (not raw)',
        () async {
          // This test validates the error interceptor chain:
          // Trigger fires → PostgrestException → mapPostgrestToDomainException
          // → IntegrityException (never leaks raw DB code to caller).
          //
          // We test this through the _ErrorMapper helper rather than the
          // repository directly, because the repository has no public update method
          // (INV-7 compliance means no update methods exist at all).
          final mapper = _ErrorMapper();
          const fakeRestrictViolation = PostgrestException(
            message:
                'telegram_evidence_uploads: fully immutable (INV-7). UPDATE blocked.',
            code: 'P0001',
            details: null,
            hint: null,
          );

          expect(
            () => throw mapper.mapPostgrestToDomainException(
              fakeRestrictViolation,
              resourceType: 'telegram_evidence_upload',
              resourceId: 'test-id',
            ),
            throwsA(
              isA<IntegrityException>().having(
                (e) => e.message,
                'message',
                contains('INV-7'),
              ),
            ),
            reason:
                'INV-10: The error interceptor must translate P0001 trigger '
                'exceptions to IntegrityException, preserving the forensic '
                'message without leaking raw PostgrestException to callers.',
          );
        },
      );

      // ── IMM-5 ──────────────────────────────────────────────────────────────
      test(
        'IMM-5: Original evidence row is unchanged after failed UPDATE attempt',
        () async {
          final originalHash = PostgresTestConfig.fakeForensicHash(
            'immutable-original',
          );
          final msgId = DateTime.now().toUtc().microsecondsSinceEpoch + 9999;
          final freshEvidenceId =
              await PostgresTestConfig.seedTelegramEvidenceUpload(
                serviceClient,
                orgId: orgA,
                driverId: driverA,
                forensicHash: originalHash,
                chatId: 300000001,
                telegramMessageId: msgId,
              );

          // Attempt tamper — expect failure.
          try {
            await serviceClient
                .from('telegram_evidence_uploads')
                .update({
                  'forensic_hash': PostgresTestConfig.fakeForensicHash(
                    'tampered',
                  ),
                })
                .eq('id', freshEvidenceId);
            // If no exception was thrown, the trigger did not fire.
            fail(
              'Expected PostgrestException from immutability trigger, '
              'but the UPDATE succeeded — INV-7 violation!',
            );
          } on PostgrestException {
            // Expected — trigger fired.
          }

          // Verify original row is intact.
          final row = await serviceClient
              .from('telegram_evidence_uploads')
              .select('forensic_hash')
              .eq('id', freshEvidenceId)
              .single();

          expect(
            row['forensic_hash'],
            equals(originalHash),
            reason:
                'INV-9: The forensic hash must be identical to the value '
                'written at INSERT time. The trigger must have rolled back '
                'the UPDATE, leaving the original hash intact.',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );

  // ===========================================================================
  // Group B — telegram_binding_tokens immutability (Task 6 — additional)
  // trg_tbt_no_immutable_update, trg_tbt_no_delete
  // ===========================================================================
  group(
    'INV-7: telegram_binding_tokens immutable fields are protected',
    () {
      late SupabaseClient serviceClient;
      late String driverA;
      late String tokenId;

      const orgA = PostgresTestConfig.testOrgId;

      setUpAll(() async {
        serviceClient = PostgresTestConfig.createServiceRoleClient();
        await PostgresTestConfig.ensureSentinelOrg(id: orgA);
        driverA = await PostgresTestConfig.seedDriver(
          serviceClient,
          orgId: orgA,
          licenseNumber: 'TBT-5001',
        );
      });

      setUp(() async {
        final seed = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
        final code = PostgresTestConfig.fakeTokenCode('tbt-$seed');
        tokenId = await PostgresTestConfig.seedBindingToken(
          serviceClient,
          orgId: orgA,
          driverId: driverA,
          code: code,
        );
      });

      tearDownAll(() async {
        await PostgresTestConfig.cleanupTelegramData(
          serviceClient,
          orgId: orgA,
        );
        await serviceClient.dispose();
      });

      // ── TBT-1 ──────────────────────────────────────────────────────────────
      test(
        'TBT-1: UPDATE organization_id is blocked by immutability trigger',
        () async {
          expect(
            () async {
              await serviceClient
                  .from('telegram_binding_tokens')
                  .update({
                    'organization_id': '00000000-0000-0000-0000-000000000002',
                  })
                  .eq('id', tokenId);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'INV-7: trg_tbt_no_immutable_update must block mutation of '
                'organization_id — token ownership is immutable after creation.',
          );
        },
      );

      // ── TBT-2 ──────────────────────────────────────────────────────────────
      test('TBT-2: UPDATE code is blocked by immutability trigger', () async {
        expect(
          () async {
            await serviceClient
                .from('telegram_binding_tokens')
                .update({'code': 'AAAABBBB'})
                .eq('id', tokenId);
          },
          throwsA(isA<PostgrestException>()),
          reason:
              'INV-7: token code is immutable. Mutation enables replay attacks.',
        );
      });

      // ── TBT-3 ──────────────────────────────────────────────────────────────
      test(
        'TBT-3: DELETE on telegram_binding_tokens is blocked by trigger',
        () async {
          expect(
            () async {
              await serviceClient
                  .from('telegram_binding_tokens')
                  .delete()
                  .eq('id', tokenId);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'INV-7: trg_tbt_no_delete must block DELETE on tokens. '
                'Forensic chain-of-custody requires audit trail preservation.',
          );
        },
      );

      // ── TBT-4 ──────────────────────────────────────────────────────────────
      test(
        'TBT-4: used_at_utc can transition NULL → timestamp (valid lifecycle)',
        () async {
          final now = DateTime.now().toUtc().toIso8601String();

          // Valid transition: NULL → timestamp (consume the token).
          await expectLater(
            serviceClient
                .from('telegram_binding_tokens')
                .update({'used_at_utc': now})
                .eq('id', tokenId),
            completes,
            reason:
                'INV-7: used_at_utc NULL → timestamp is the only allowed '
                'mutation on telegram_binding_tokens (token consumption).',
          );
        },
      );

      // ── TBT-5 ──────────────────────────────────────────────────────────────
      test(
        'TBT-5: used_at_utc timestamp → different timestamp is blocked (once-only)',
        () async {
          // First, consume the token.
          final first = DateTime.now().toUtc().toIso8601String();
          await serviceClient
              .from('telegram_binding_tokens')
              .update({'used_at_utc': first})
              .eq('id', tokenId);

          // Attempt to change used_at_utc again — must be blocked.
          final second = DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 1))
              .toIso8601String();

          expect(
            () async {
              await serviceClient
                  .from('telegram_binding_tokens')
                  .update({'used_at_utc': second})
                  .eq('id', tokenId);
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'INV-7: used_at_utc is a one-way latch. '
                'Once stamped, it must never change — '
                'prevents token replay after consumption.',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );

  // ===========================================================================
  // Group C — BasePostgresRepository hash utilities (always runs, no DB)
  // ===========================================================================
  group('INV-9: BasePostgresRepository forensic hash utilities', () {
    // ── HASH-1 ─────────────────────────────────────────────────────────────
    test('HASH-1: hashPayload produces 64-char hex SHA-256 digest', () {
      const payload = {
        'organization_id': 'org-a',
        'forensic_hash': 'abc123',
        'storage_path': '/org-a/telegram/100/file.jpg',
      };
      final hash = BasePostgresRepository.hashPayload(payload);
      expect(hash, isNotNull);
      expect(hash!.length, equals(64));
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(hash),
        isTrue,
        reason: 'INV-9: Hash must be a valid hex SHA-256 string.',
      );
    });

    // ── HASH-2 ─────────────────────────────────────────────────────────────
    test(
      'HASH-2: hashPayload is deterministic for identical payloads (INV-15)',
      () {
        final payload = {'z_key': 'last', 'a_key': 'first', 'm_key': 'middle'};
        final h1 = BasePostgresRepository.hashPayload(payload);
        final h2 = BasePostgresRepository.hashPayload(payload);
        expect(h1, equals(h2), reason: 'INV-15: Hash must be deterministic.');
      },
    );

    // ── HASH-3 ─────────────────────────────────────────────────────────────
    test(
      'HASH-3: hashPayload is key-order independent (canonical JSON — INV-15)',
      () {
        final payload1 = {'a': 1, 'b': 2};
        final payload2 = {'b': 2, 'a': 1};
        final h1 = BasePostgresRepository.hashPayload(payload1);
        final h2 = BasePostgresRepository.hashPayload(payload2);
        expect(
          h1,
          equals(h2),
          reason:
              'INV-15: Keys must be sorted before hashing to ensure '
              'identical output regardless of Map insertion order.',
        );
      },
    );

    // ── HASH-4 ─────────────────────────────────────────────────────────────
    test('HASH-4: hashPayload null or empty returns null', () {
      expect(BasePostgresRepository.hashPayload(null), isNull);
      expect(BasePostgresRepository.hashPayload({}), isNull);
    });

    // ── HASH-5 ─────────────────────────────────────────────────────────────
    test(
      'HASH-5: sortKeys normalizes DateTime to ISO-8601 Z suffix (INV-9)',
      () {
        final dt = DateTime.utc(2026, 4, 20, 12, 0, 0);
        final result = BasePostgresRepository.sortKeys({'ts': dt});
        expect(
          (result as Map)['ts'],
          endsWith('Z'),
          reason:
              'INV-9: DateTime must serialize with Z suffix for Deno parity.',
        );
      },
    );
  });
}
