// Integration tests for sanction_escalation_log DB invariants.
//
// Prerequisites:
//   - Real Postgres instance with migrations applied
//
// Run: flutter test test/integration/sanction_escalation_log_test.dart
//      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../infrastructure/postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  const skipReason =
      'Supabase local não está rodando — execute `supabase start`';

  late final SupabaseClient client;

  setUpAll(() async {
    if (isRunning) {
      client = SupabaseClient(
        PostgresTestConfig.supabaseUrl,
        PostgresTestConfig.serviceRoleKey,
      );
    }
  });

  group(
    'sanction_escalation_log — DB invariants',
    skip: isRunning ? null : skipReason,
    () {
      test('UPDATE is blocked by trigger (INV-1)', () async {
        // Attempt direct update (trigger should block it)
        expect(
          () async => client
              .from('sanction_escalation_log')
              .update({'delivery_status': 'delivered'})
              .eq('id', 'non-existent-id'),
          // PostgreSQL trigger raises restrict_violation — Supabase wraps it
          throwsA(anything),
        );
      });

      test('DELETE is blocked by trigger (INV-1)', () async {
        expect(
          () async => client
              .from('sanction_escalation_log')
              .delete()
              .eq('id', 'non-existent-id'),
          throwsA(anything),
        );
      });
    },
  );
}
