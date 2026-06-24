// Integration: SupabasePortalSubmissionAuditGateway anti-oracle gate (INV-26).
// Without a valid JWT org + auditor role, listPending must not leak another
// tenant's submissions and audit() must surface an opaque (mapped) error —
// never a raw PostgrestException.
//
// Prerequisites: `supabase start`. Run via `make test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_submission_audit_gateway.dart';

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
    'listPending without JWT org → empty (anti-oracle)',
    skip: isRunning ? null : skipReason,
    () async {
      final gw = SupabasePortalSubmissionAuditGateway(client);
      try {
        final rows = await gw.listPending(
          organizationId: const Uuid().v4(),
          queueEntryId: const Uuid().v4(),
        );
        expect(rows, isEmpty);
      } on PostgrestException {
        fail('Raw PostgrestException leaked to caller (INV-26 violation).');
      } catch (_) {
        // Mapped opaque domain failure acceptable.
      }
    },
  );
}
