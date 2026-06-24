// Integration: SupabasePortalDisputeGateway anti-oracle gate (INV-26).
// An invalid/expired/revoked token is indistinguishable: read + acknowledge
// both surface the same opaque PortalDisputeException, never a raw infra error.
//
// Prerequisites: `supabase start`. Run via `make test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_dispute_gateway.dart';

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
      PostgresTestConfig.supabaseAnonKey,
    );
  });
  tearDownAll(() async {
    if (!isRunning) return;
    await client.dispose();
  });

  test(
    'read(invalid token) → PortalDisputeException',
    skip: isRunning ? null : skipReason,
    () async {
      final gw = SupabasePortalDisputeGateway(client);
      await expectLater(
        gw.read(const Uuid().v4()),
        throwsA(isA<PortalDisputeException>()),
      );
    },
  );

  test(
    'acknowledge(invalid token) → PortalDisputeException',
    skip: isRunning ? null : skipReason,
    () async {
      final gw = SupabasePortalDisputeGateway(client);
      await expectLater(
        gw.acknowledge(token: const Uuid().v4(), snapshotHash: 'a' * 64),
        throwsA(isA<PortalDisputeException>()),
      );
    },
  );
}
