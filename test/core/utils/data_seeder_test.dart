import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/utils/data_seeder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../infrastructure/postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'DataSeeder Integration Tests',
    () {
      late SupabaseClient client;
      late String organizationId;
      late DataSeeder seeder;

      setUpAll(() async {
        if (isRunning) {
          organizationId = const Uuid().v4();
          client = await PostgresTestConfig.createClient();

          // Seed the organization to satisfy FK constraints in other tables
          await client.from('organizations').insert({
            'id': organizationId,
            'name': 'DataSeeder Test Org ${organizationId.substring(0, 8)}',
          });

          seeder = DataSeeder(client, organizationId: organizationId);

          // No clean up needed as we use a fresh organizationId per run.
          // Note: sla_audit_ledger_v2 is immutable (INV-1), so DELETE is illegal.
        }
      });

      test('seedDrivers inserts default drivers', () async {
        await seeder.seedDrivers();

        final drivers = await client
            .from('drivers')
            .select()
            .eq('organization_id', organizationId);

        expect(drivers.length, 3);
        expect(drivers.any((d) => d['full_name'] == 'João Silva'), isTrue);
      });

      test('seedRoutes inserts default routes', () async {
        await seeder.seedRoutes();

        final routes = await client
            .from('routes')
            .select()
            .eq('organization_id', organizationId);

        expect(routes.length, 4);
        expect(routes.any((r) => r['gtfs_route_id'] == '809U-10'), isTrue);
      });

      test('seedActiveSanctions creates recommendations', () async {
        // DataSeeder needs a contract for this
        final contractId = const Uuid().v4();
        await client.from('contracts').insert({
          'id': contractId,
          'organization_id': organizationId,
          'name': 'Seeder Test Contract',
          'contractor_name': 'Test Contractor',
          'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
          'valid_until_utc': DateTime.now()
              .toUtc()
              .add(const Duration(days: 30))
              .toIso8601String(),
          'status': 'active',
        });

        await seeder.seedActiveSanctions();

        final ledger = await client
            .from('sla_audit_ledger_v2')
            .select()
            .eq('organization_id', organizationId)
            .eq('type', 'SANCTION_RECOMMENDED');

        expect(ledger.length, 1);
      });
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
