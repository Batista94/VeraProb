// Integration: PostgresContractualRuleRepository.
// For an org/contract with no rule set, the active snapshot is empty (INV-21:
// scheduled rules never leak; a missing set yields an empty, replay-stable
// snapshot rather than an error).
//
// Prerequisites: `supabase start`. Run via `make test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_rule_repository.dart';

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
    'missing rule set → empty active snapshot',
    skip: isRunning ? null : skipReason,
    () async {
      final repo = PostgresContractualRuleRepository(client);
      final snapshot = await repo.getActiveSnapshotForContract(
        const Uuid().v4(),
        const Uuid().v4(),
      );
      expect(snapshot, isA<RuleSnapshot>());
      expect(snapshot.rules, isEmpty);
    },
  );
}
