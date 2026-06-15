// Integration: PostgresRuleStudioCommandService (INV-10 / INV-26).
// update_contractual_rule gates JWT org + TENANT_ADMIN role and RAISEs (P0001) on
// any guard violation. A service-role caller has no org context, so the guard
// fires; the service MUST translate that to a typed IntegrityException — never a
// raw PostgrestException leaking the DB code across the infrastructure boundary.
//
// Prerequisites: `supabase start`. Run via `make test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_rule_studio_command_service.dart';

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
    'updateRule without authority → IntegrityException (no raw infra leak)',
    skip: isRunning ? null : skipReason,
    () async {
      final svc = PostgresRuleStudioCommandService(client);
      await expectLater(
        svc.updateRule(
          contractId: const Uuid().v4(),
          oldRuleId: null,
          ruleType: SlaRuleType.maxToleranceDelay,
          newConfig: const {'threshold_minutes': 30},
          evaluationOrder: 1,
          effectiveAtUtc: DateTime.utc(2026, 6, 1),
        ),
        throwsA(isA<IntegrityException>()),
      );
    },
  );
}
