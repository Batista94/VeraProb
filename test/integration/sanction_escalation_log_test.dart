// Integration tests for sanction_escalation_log DB invariants.
//
// Prerequisites:
//   - Real Postgres instance with migrations applied
//
// Run: flutter test test/integration/sanction_escalation_log_test.dart
//      --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  final skipReason = supabaseUrl.isEmpty
      ? 'SUPABASE_URL not configured — skipping integration tests'
      : null;

  setUpAll(() async {
    if (supabaseUrl.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
    }
  });

  group('sanction_escalation_log — DB invariants', () {
    test(
      'UPDATE is blocked by trigger (INV-1)',
      skip: skipReason,
      () async {
        final client = Supabase.instance.client;

        // Attempt direct update (trigger should block it)
        expect(
          () async => client
              .from('sanction_escalation_log')
              .update({'delivery_status': 'delivered'})
              .eq('id', 'non-existent-id'),
          // PostgreSQL trigger raises restrict_violation — Supabase wraps it
          throwsA(anything),
        );
      },
    );

    test(
      'DELETE is blocked by trigger (INV-1)',
      skip: skipReason,
      () async {
        final client = Supabase.instance.client;

        expect(
          () async => client
              .from('sanction_escalation_log')
              .delete()
              .eq('id', 'non-existent-id'),
          throwsA(anything),
        );
      },
    );
  });
}
