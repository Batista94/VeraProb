/// Integration test — RED phase
///
/// Verifies that [super_admin_tenant_health_view] exposes `cnpj` and
/// `created_at` columns (regression guard for migration 20260705000002 which
/// dropped them).
///
/// INV-3: view is an audit surface — column removal = data loss regression.
/// INV-6: created_at must be TIMESTAMPTZ (UTC).
/// INV-22: security_invoker = true must survive DROP+CREATE.
/// INV-24: only service_role may SELECT the view.
///
/// Run:
///   flutter test test/infrastructure/postgres/super_admin_tenant_health_view_columns_test.dart
///
/// Requires: supabase start
@Tags(['postgres', 'integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'postgres_test_config.dart';

void main() {
  const uuid = Uuid();

  group(
    'super_admin_tenant_health_view — cnpj + created_at columns (INV-3/INV-6)',
    skip: PostgresTestConfig.isSupabaseRunning().then(
      (ok) => ok
          ? null
          : 'Supabase local não está rodando. Execute: supabase start',
    ),
    () {
      late SupabaseClient serviceClient;
      late String orgId;

      setUpAll(() async {
        await PostgresTestConfig.reloadPostgrestSchema();
        serviceClient = PostgresTestConfig.createServiceRoleClient();
      });

      setUp(() async {
        orgId = uuid.v4();
        // Seed a minimal org with a known cnpj so we can assert round-trip.
        await serviceClient.from('organizations').insert({
          'id': orgId,
          'name': 'View Column Test Org',
          'cnpj': '12345678000195',
          'timezone': 'America/Sao_Paulo',
          'currency_code': 'BRL',
          'plan_type': 'starter',
          'tool_cost_cents': 0,
        });
      });

      tearDown(() async {
        // Cleanup in FK-safe order (no append-only tables touched).
        await serviceClient.from('organizations').delete().eq('id', orgId);
      });

      tearDownAll(() async {
        await serviceClient.dispose();
      });

      // ── RED: this test FAILS before the fix migration is applied ──────────

      test('view exposes cnpj column with correct value', () async {
        final rows = await serviceClient
            .from('super_admin_tenant_health_view')
            .select('id, cnpj')
            .eq('id', orgId);

        expect(rows, hasLength(1));
        expect(
          rows.first['cnpj'],
          equals('12345678000195'),
          reason:
              'cnpj was dropped by migration 20260705000002 — '
              'must be restored (INV-3)',
        );
      });

      test(
        'view exposes created_at column as non-null TIMESTAMPTZ (INV-6)',
        () async {
          final rows = await serviceClient
              .from('super_admin_tenant_health_view')
              .select('id, created_at')
              .eq('id', orgId);

          expect(rows, hasLength(1));

          final raw = rows.first['created_at'];
          expect(
            raw,
            isNotNull,
            reason:
                'created_at was dropped by migration 20260705000002 — '
                'must be restored (INV-3/INV-6)',
          );

          // INV-6: must parse as UTC DateTime without throwing.
          final parsed = DateTime.parse(raw as String);
          expect(
            parsed.isUtc,
            isTrue,
            reason: 'created_at must be TIMESTAMPTZ (UTC) per INV-6',
          );
        },
      );

      test(
        'list_tenant_health select contract matches edge function column list',
        () async {
          // Mirrors the exact select string used in super-admin-proxy index.ts
          // for action=list_tenant_health. If any column is missing the query
          // throws a PostgREST 400 (column not found) which surfaces as 500 to
          // the Flutter client.
          const edgeFunctionSelect =
              'id,name,legal_name,plan_type,is_active,status,'
              'max_vehicles,max_active_contracts,capabilities,tool_cost_cents,'
              'dwell_time_seconds,billing_day,contact_email,external_id,'
              'organization_type,updated_at,cnpj,created_at,'
              'active_contract_count,last_telemetry_at,open_critical_alert_count';

          // Should not throw — if cnpj or created_at are absent PostgREST
          // returns a 400 which the Dart client surfaces as an exception.
          final rows = await serviceClient
              .from('super_admin_tenant_health_view')
              .select(edgeFunctionSelect)
              .eq('id', orgId);

          expect(rows, hasLength(1));
        },
      );
    },
  );
}
