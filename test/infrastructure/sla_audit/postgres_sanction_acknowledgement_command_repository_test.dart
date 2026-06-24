// Integration: PostgresSanctionAcknowledgementCommandRepository (INV-26).
// acknowledge_sanction_internal REVOKEs EXECUTE from service_role; a service-role
// caller is denied (42501) and the repo MUST map that to a typed
// SovereigntyViolationException — never a raw PostgrestException leaking the DB code.
//
// Prerequisites: `supabase start`. Run via `make test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_acknowledgement_command_repository.dart';

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

  test(
    'acknowledgeInternal without authority → SovereigntyViolationException',
    skip: isRunning ? null : skipReason,
    () async {
      final repo = PostgresSanctionAcknowledgementCommandRepository(client);
      await expectLater(
        repo.acknowledgeInternal(
          organizationId: const Uuid().v4(),
          queueEntryId: const Uuid().v4(),
          acknowledgedByUserId: const Uuid().v4(),
        ),
        throwsA(isA<SovereigntyViolationException>()),
      );
    },
  );
}
