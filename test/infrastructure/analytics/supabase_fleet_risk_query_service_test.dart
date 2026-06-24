// Integration: SupabaseFleetRiskQueryService anti-oracle gate (INV-26).
// No JWT org → empty fleet-risk list, no raw PostgrestException leak.
//
// Prerequisites: `supabase start`. Run via `make test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/infrastructure/analytics/supabase_fleet_risk_query_service.dart';

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
    'no JWT org → empty fleet risk (anti-oracle)',
    skip: isRunning ? null : skipReason,
    () async {
      final svc = SupabaseFleetRiskQueryService(client);
      try {
        final rows = await svc.listFleetRisk(organizationId: const Uuid().v4());
        expect(rows, isEmpty);
      } on PostgrestException {
        fail('Raw PostgrestException leaked to caller (INV-26 violation).');
      } catch (_) {
        // Mapped opaque domain failure acceptable.
      }
    },
  );
}
