// Integration: PostgresSanctionReviewCommandRepository (INV-26 / INV-10).
// A service-role caller (no JWT org/role) hitting the verdict RPCs is denied by
// the in-RPC org/role guard (42501); the repo MUST map that to a typed
// SovereigntyViolationException — never a raw PostgrestException leaking the DB code.
//
// Prerequisites: `supabase start`. Run via `make test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_review_command_repository.dart';

import '../postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  late final SupabaseClient client;
  setUpAll(() async {
    if (!isRunning) return;
    client = SupabaseClient(
      PostgresTestConfig.supabaseUrl,
      PostgresTestConfig.serviceRoleKey,
    );
  });
  tearDownAll(() async {
    if (!isRunning) return;
    await client.dispose();
  });

  final now = DateTime.utc(2026, 6, 1);

  test(
    'approveSanction without authority → SovereigntyViolationException',
    skip: isRunning ? null : skipReason,
    () async {
      final repo = PostgresSanctionReviewCommandRepository(client);
      await expectLater(
        repo.approveSanction(
          organizationId: const Uuid().v4(),
          queueEntryId: const Uuid().v4(),
          reviewedByUserId: const Uuid().v4(),
          actorEmail: 'a@x.com',
          occurredAtUtc: now,
        ),
        throwsA(isA<SovereigntyViolationException>()),
      );
    },
  );

  test(
    'disputeSanction without authority → SovereigntyViolationException',
    skip: isRunning ? null : skipReason,
    () async {
      final repo = PostgresSanctionReviewCommandRepository(client);
      await expectLater(
        repo.disputeSanction(
          organizationId: const Uuid().v4(),
          queueEntryId: const Uuid().v4(),
          disputedByUserId: const Uuid().v4(),
          actorEmail: 'a@x.com',
          occurredAtUtc: now,
        ),
        throwsA(isA<SovereigntyViolationException>()),
      );
    },
  );
}
