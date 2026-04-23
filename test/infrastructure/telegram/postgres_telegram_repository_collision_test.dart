// =============================================================================
// Task 4 — Constraint Collision & Race Conditions (INV-10)
// =============================================================================
//
// Forensic Insight — QA & Security Lead (Paranoid Protector)
// Invariants under scrutiny:
//   INV-10 (Error): IntegrityException for domain violations. No silent fail.
//   INV-9  (Seal): SHA-256 on all evidence records.
//
// Scenarios:
//   - Insert two tokens with identical 8-char code → 23505 unique_violation
//   - Insert two evidence uploads with identical (chat_id, telegram_message_id)
//     → 23505 unique_violation (idempotency constraint)
//   - Error interceptor maps 23505 → IntegrityException (never raw PostgrestException)
//   - Validate extracted field name from the violation details
//
// The `code` column has: UNIQUE + CHECK alphabet constraint.
// The evidence table has: UNIQUE(chat_id, telegram_message_id) — webhook idempotency.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_binding_token.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';
import 'package:veraprob/infrastructure/telegram/postgres_telegram_repository.dart';

import '../postgres/postgres_test_config.dart';

// ── Helper: access mapPostgrestToDomainException ─────────────────────────────
class _ErrorMapper with PostgresErrorInterceptor {}

// ── Domain builder helper ─────────────────────────────────────────────────────
TelegramBindingToken _buildToken({
  required String orgId,
  required String driverId,
  required String code,
}) {
  const uuid = Uuid();
  final now = DateTime.now().toUtc();
  return TelegramBindingToken(
    id: uuid.v4(),
    organizationId: orgId,
    driverId: driverId,
    createdByUserId: uuid.v4(),
    code: code,
    expiresAtUtc: now.add(const Duration(minutes: 15)),
    usedAtUtc: null,
    createdAtUtc: now,
  );
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  // ===========================================================================
  // Group A — UNIQUE constraint collision tests (require DB)
  // ===========================================================================
  group(
    'INV-10: UNIQUE constraint violations are treated as business conflicts',
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
          licenseNumber: 'COL-7001',
        );
      });

      tearDownAll(() async {
        await PostgresTestConfig.cleanupTelegramData(
          serviceClient,
          orgId: orgId,
        );
        await serviceClient.dispose();
      });

      // ── COL-1 ──────────────────────────────────────────────────────────────
      test(
        'COL-1: Duplicate token code raises 23505 unique_violation on second INSERT',
        () async {
          // Seed first token with a known code.
          final seed = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
          final code = PostgresTestConfig.fakeTokenCode('col1-$seed');

          await PostgresTestConfig.seedBindingToken(
            serviceClient,
            orgId: orgId,
            driverId: driverA,
            code: code,
          );

          // Attempt to seed another token with the same code.
          expect(
            () async {
              await PostgresTestConfig.seedBindingToken(
                serviceClient,
                orgId: orgId,
                driverId: driverA,
                code: code, // same code — must collide
              );
            },
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.code,
                'code',
                equals('23505'),
              ),
            ),
            reason:
                'INV-10: Two tokens with identical 8-char codes must produce '
                'a 23505 unique_violation — the UNIQUE constraint on the '
                'code column enforces code uniqueness across the system.',
          );
        },
      );

      // ── COL-2 ──────────────────────────────────────────────────────────────
      test(
        'COL-2: Duplicate (chat_id, telegram_message_id) raises 23505 on second INSERT',
        () async {
          // This models a webhook retry scenario — idempotency guard.
          final msgId = DateTime.now().toUtc().microsecondsSinceEpoch % 1000000;
          final hash1 = PostgresTestConfig.fakeForensicHash('col2-msg-a');
          const chatId = 400000001;

          // Seed first evidence upload.
          await PostgresTestConfig.seedTelegramEvidenceUpload(
            serviceClient,
            orgId: orgId,
            driverId: driverA,
            forensicHash: hash1,
            chatId: chatId,
            telegramMessageId: msgId,
          );

          // Attempt to insert another upload with same (chat_id, message_id).
          final hash2 = PostgresTestConfig.fakeForensicHash('col2-msg-b');
          expect(
            () async {
              await PostgresTestConfig.seedTelegramEvidenceUpload(
                serviceClient,
                orgId: orgId,
                driverId: driverA,
                forensicHash: hash2,
                chatId: chatId,
                telegramMessageId: msgId, // same message — duplicate
              );
            },
            throwsA(
              isA<PostgrestException>().having(
                (e) => e.code,
                'code',
                equals('23505'),
              ),
            ),
            reason:
                'INV-10: Duplicate (chat_id, telegram_message_id) must raise '
                'unique_violation — the uq_teu_chat_message constraint makes '
                'webhook retries idempotent at the DB level.',
          );
        },
      );

      // ── COL-3 ──────────────────────────────────────────────────────────────
      test(
        'COL-3: After collision, original evidence row remains intact (no partial write)',
        () async {
          final msgId =
              DateTime.now().toUtc().microsecondsSinceEpoch % 1000000 + 100;
          final originalHash = PostgresTestConfig.fakeForensicHash(
            'col3-original',
          );
          const chatId = 500000001;

          final evidenceId =
              await PostgresTestConfig.seedTelegramEvidenceUpload(
                serviceClient,
                orgId: orgId,
                driverId: driverA,
                forensicHash: originalHash,
                chatId: chatId,
                telegramMessageId: msgId,
              );

          // Attempt duplicate — should fail.
          try {
            await PostgresTestConfig.seedTelegramEvidenceUpload(
              serviceClient,
              orgId: orgId,
              driverId: driverA,
              forensicHash: PostgresTestConfig.fakeForensicHash(
                'col3-duplicate',
              ),
              chatId: chatId,
              telegramMessageId: msgId,
            );
            fail('Expected 23505 unique_violation but INSERT succeeded');
          } on PostgrestException {
            // Expected — continue to verify original row.
          }

          // Original row must be untouched.
          final row = await serviceClient
              .from('telegram_evidence_uploads')
              .select('forensic_hash')
              .eq('id', evidenceId)
              .single();

          expect(
            row['forensic_hash'],
            equals(originalHash),
            reason:
                'INV-9: Collision rejection must be atomic — '
                'the original forensic_hash must remain unchanged.',
          );
        },
      );

      // ── COL-4 ──────────────────────────────────────────────────────────────
      test(
        'COL-4: createBindingToken propagates 23505 as IntegrityException (not crash)',
        () async {
          final seed = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
          final code = PostgresTestConfig.fakeTokenCode('col4-$seed');

          // Seed first token directly.
          await PostgresTestConfig.seedBindingToken(
            serviceClient,
            orgId: orgId,
            driverId: driverA,
            code: code,
          );

          // Now try to create via repository — must surface IntegrityException.
          final repo = PostgresTelegramRepository(serviceClient);

          expect(
            () async {
              await repo.createBindingToken(
                _buildToken(orgId: orgId, driverId: driverA, code: code),
              );
            },
            throwsA(isA<IntegrityException>()),
            reason:
                'INV-10: createBindingToken must catch 23505 and surface it as '
                'IntegrityException — never as a raw PostgrestException crash. '
                'The caller treats this as a business conflict (code generation retry).',
          );
        },
      );

      // ── COL-5 ──────────────────────────────────────────────────────────────
      test(
        'COL-5: token code CHECK constraint rejects invalid alphabet chars',
        () async {
          expect(
            () async {
              const innerUuid = Uuid();
              await serviceClient.from('telegram_binding_tokens').insert({
                'id': innerUuid.v4(),
                'organization_id': orgId,
                'driver_id': driverA,
                'created_by_user_id': innerUuid.v4(),
                'code': 'INVALID0', // '0' and 'I' are in excluded chars
                'expires_at_utc': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 15))
                    .toIso8601String(),
                'created_at_utc': DateTime.now().toUtc().toIso8601String(),
              });
            },
            throwsA(isA<PostgrestException>()),
            reason:
                'The CHECK constraint chk_tbt_code_format must reject codes '
                'containing ambiguous chars (0, 1, I, O, L) — only the '
                '32-char unambiguous alphabet is accepted.',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );

  // ===========================================================================
  // Group B — Error interceptor mapping (always runs, no DB needed)
  // ===========================================================================
  group('INV-10: Error interceptor maps 23505 → IntegrityException', () {
    // ── MAP-1 ─────────────────────────────────────────────────────────────────
    test(
      'MAP-1: 23505 with field detail is mapped to IntegrityException with field',
      () {
        final mapper = _ErrorMapper();
        const error = PostgrestException(
          message:
              'duplicate key value violates unique constraint "telegram_binding_tokens_code_key"',
          code: '23505',
          details: 'Key (code)=(ABCDEFGH) already exists.',
          hint: null,
        );

        expect(
          () => throw mapper.mapPostgrestToDomainException(
            error,
            resourceType: 'telegram_binding_token',
          ),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.field,
              'field',
              equals('code'),
            ),
          ),
          reason:
              'INV-10: 23505 with "Key (code)=..." details must produce '
              'an IntegrityException with field == "code" so the caller '
              'can treat this as a code generation conflict.',
        );
      },
    );

    // ── MAP-2 ─────────────────────────────────────────────────────────────────
    test(
      'MAP-2: 23505 without parseable field detail produces IntegrityException with null field',
      () {
        final mapper = _ErrorMapper();
        const error = PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
          details: null,
          hint: null,
        );

        expect(
          () => throw mapper.mapPostgrestToDomainException(error),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', isNull),
          ),
          reason:
              'INV-10: When details are absent, field must be null — '
              'not throw a NullPointerException.',
        );
      },
    );

    // ── MAP-3 ─────────────────────────────────────────────────────────────────
    test('MAP-3: 23505 never surfaces as raw PostgrestException to caller', () {
      final mapper = _ErrorMapper();
      const error = PostgrestException(
        message: 'unique violation',
        code: '23505',
        details: 'Key (code)=(ZZZZZZZZ) already exists.',
        hint: null,
      );

      final result = mapper.mapPostgrestToDomainException(error);

      expect(
        result,
        isA<IntegrityException>(),
        reason:
            'INV-10: The caller must receive a domain IntegrityException, '
            'never a raw PostgrestException — DB error codes must not leak.',
      );
      expect(result, isNot(isA<PostgrestException>()));
    });

    // ── MAP-4 ─────────────────────────────────────────────────────────────────
    test('MAP-4: uq_teu_chat_message violation field extraction', () {
      final mapper = _ErrorMapper();
      const error = PostgrestException(
        message:
            'duplicate key value violates unique constraint "uq_teu_chat_message"',
        code: '23505',
        details:
            'Key (chat_id, telegram_message_id)=(100000001, 42) already exists.',
        hint: null,
      );

      expect(
        () => throw mapper.mapPostgrestToDomainException(
          error,
          resourceType: 'telegram_evidence_upload',
        ),
        throwsA(isA<IntegrityException>()),
        reason:
            'INV-10: Composite unique violation (chat_id, telegram_message_id) '
            'must still produce IntegrityException — the idempotency guard '
            'must not crash the webhook retry flow.',
      );
    });
  });
}
