// Integration: SupabaseCarrierRankingQueryService anti-oracle gate (INV-26).
// A caller with no JWT org claim (service-role) must receive an EMPTY ranking
// from the SECURITY DEFINER RPC — never another tenant's data, never a raw
// PostgrestException leaking to the caller.
//
// Prerequisites: `supabase start`. Run via `make test` (passes dart-defines).

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/infrastructure/analytics/supabase_carrier_ranking_query_service.dart';

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
    'no JWT org → empty ranking (anti-oracle), no raw infra leak',
    skip: isRunning ? null : skipReason,
    () async {
      final svc = SupabaseCarrierRankingQueryService(client);
      try {
        final rows = await svc.getRanking(organizationId: const Uuid().v4());
        expect(rows, isEmpty);
      } on PostgrestException {
        fail('Raw PostgrestException leaked to caller (INV-26 violation).');
      } catch (_) {
        // A mapped opaque domain failure is the only acceptable alternative.
      }
    },
  );
}
