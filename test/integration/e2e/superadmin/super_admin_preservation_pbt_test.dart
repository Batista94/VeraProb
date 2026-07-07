/// Property-Based Test: Preservation — Org Creation and Billing Event Behavior Unchanged
///
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
///
/// Property 2: For all valid inputs, the fixed function (single 18-param overload
/// with p_allowed_domains) creates an `organizations` row and a `tenant_billing_events`
/// row with expected values. This confirms baseline behavior is preserved after fix.
///
/// After fix migration 20260505000000: there is only ONE correct overload.
/// The broken overload from 20260504000004 and the test helper were dropped.
///
/// Requires Supabase local rodando com migrations aplicadas.
/// Comando:
///   flutter test test/integration/e2e/superadmin/super_admin_preservation_pbt_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();

int _cnpjCounter = 0;

/// Generates a unique 14-digit CNPJ-like string for test isolation.
String _uniqueCnpj() {
  _cnpjCounter++;
  final ts = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  final paddedCounter = _cnpjCounter.toString().padLeft(4, '0');
  final combined = '$ts$paddedCounter'.padLeft(14, '0');
  return combined.substring(combined.length - 14);
}

/// Valid plan types accepted by the RPC.
const _validPlanTypes = ['starter', 'professional', 'enterprise'];

/// Input record for property-based test generation.
class _OrgInput {
  final String tradeName;
  final String legalName;
  final String planType;
  final int maxVehicles;
  final int maxContracts;
  final int toolCostCents;

  const _OrgInput({
    required this.tradeName,
    required this.legalName,
    required this.planType,
    required this.maxVehicles,
    required this.maxContracts,
    required this.toolCostCents,
  });
}

/// Generates random valid org inputs using glados generators.
List<_OrgInput> _generateInputs(int count) {
  final random = Random(42);
  final tradeNameGen = any.nonEmptyLetterOrDigits;
  final legalNameGen = any.nonEmptyLetterOrDigits;
  final planTypeGen = any.choose(_validPlanTypes);
  final maxVehiclesGen = any.intInRange(1, 500);
  final maxContractsGen = any.intInRange(1, 200);
  final toolCostGen = any.intInRange(1, 5000000);

  return List.generate(count, (i) {
    final size = i + 5;
    return _OrgInput(
      tradeName: tradeNameGen(random, size).value,
      legalName: legalNameGen(random, size).value,
      planType: planTypeGen(random, size).value,
      maxVehicles: maxVehiclesGen(random, size).value,
      maxContracts: maxContractsGen(random, size).value,
      toolCostCents: toolCostGen(random, size).value,
    );
  });
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'Property 2: Preservation — Org Creation and Billing Event Behavior Unchanged',
    skip: !isRunning
        ? 'Supabase local não está rodando. Execute: supabase start'
        : null,
    () {
      late SupabaseClient serviceRoleClient;

      setUpAll(() async {
        await PostgresTestConfig.createClient();
        serviceRoleClient = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );

        // After the fix migration (20260505000000), there is only ONE correct
        // overload of super_admin_create_organization (18 params with
        // p_allowed_domains). The broken overload and the test helper
        // test_drop_broken_create_org_overload() were both dropped by the fix.
        // No disambiguation needed — PostgREST resolves unambiguously.
      });

      tearDownAll(() async {
        try {
          await Supabase.instance.dispose();
        } catch (_) {}
        await serviceRoleClient.dispose();
      });

      // Pre-generate 20 random valid inputs using glados generators
      final inputs = _generateInputs(20);

      // ── Property 2.1: Org row created with correct fields ──────────────────
      // For all valid inputs, the organizations row is created with correct
      // name, plan_type, max_vehicles, max_active_contracts.

      for (var i = 0; i < inputs.length; i++) {
        final input = inputs[i];

        test(
          'P2.1 iter $i: organizations row created with correct name="${input.tradeName.length > 15 ? '${input.tradeName.substring(0, 15)}…' : input.tradeName}", '
          'plan=${input.planType}, vehicles=${input.maxVehicles}',
          () async {
            final cnpj = _uniqueCnpj();
            final superAdminUserId = _uuid.v4();

            // Function returns TABLE(org_id UUID, plaintext_secret TEXT) since
            // migration 20260706000010; extract org_id from first row.
            final rows = await serviceRoleClient.rpc<List<dynamic>>(
              'super_admin_create_organization',
              params: {
                'p_legal_name': input.legalName,
                'p_trade_name': input.tradeName,
                'p_cnpj': cnpj,
                'p_timezone': 'America/Sao_Paulo',
                'p_currency_code': 'BRL',
                'p_plan_type': input.planType,
                'p_max_vehicles': input.maxVehicles,
                'p_max_active_contracts': input.maxContracts,
                'p_super_admin_user_id': superAdminUserId,
                'p_tool_cost_cents': input.toolCostCents,
                'p_reason': 'PBT preservation test iter $i',
              },
            );
            final orgId =
                (rows.first as Map<String, dynamic>)['org_id'] as String;

            // Verify organizations row
            final org = await serviceRoleClient
                .from('organizations')
                .select()
                .eq('id', orgId)
                .single();

            expect(
              org['name'],
              equals(input.tradeName),
              reason: 'Org name must equal p_trade_name',
            );
            expect(
              org['plan_type'],
              equals(input.planType),
              reason: 'Org plan_type must match input',
            );
            expect(
              org['max_vehicles'],
              equals(input.maxVehicles),
              reason: 'Org max_vehicles must match input',
            );
            expect(
              org['max_active_contracts'],
              equals(input.maxContracts),
              reason: 'Org max_active_contracts must match input',
            );
            expect(
              org['is_active'],
              isTrue,
              reason:
                  'Org must be active (status=ACTIVE → generated is_active=true)',
            );
          },
        );
      }

      // ── Property 2.2: Billing event created with correct fields ────────────
      // For all valid inputs, a tenant_billing_events row is created with
      // event_type='ORG_CREATED', correct plan, quotas, and super_admin_user_id.

      for (var i = 0; i < inputs.length; i++) {
        final input = inputs[i];

        test(
          'P2.2 iter $i: billing event ORG_CREATED with plan=${input.planType}, '
          'vehicles=${input.maxVehicles}, contracts=${input.maxContracts}',
          () async {
            final cnpj = _uniqueCnpj();
            final superAdminUserId = _uuid.v4();

            final rows = await serviceRoleClient.rpc<List<dynamic>>(
              'super_admin_create_organization',
              params: {
                'p_legal_name': input.legalName,
                'p_trade_name': input.tradeName,
                'p_cnpj': cnpj,
                'p_timezone': 'UTC',
                'p_currency_code': 'USD',
                'p_plan_type': input.planType,
                'p_max_vehicles': input.maxVehicles,
                'p_max_active_contracts': input.maxContracts,
                'p_super_admin_user_id': superAdminUserId,
                'p_tool_cost_cents': input.toolCostCents,
                'p_reason': 'PBT billing preservation iter $i',
              },
            );
            final orgId =
                (rows.first as Map<String, dynamic>)['org_id'] as String;

            // Verify billing event
            final events = await serviceRoleClient
                .from('tenant_billing_events')
                .select()
                .eq('organization_id', orgId)
                .eq('event_type', 'ORG_CREATED');

            expect(
              events,
              isNotEmpty,
              reason: 'Must have ORG_CREATED billing event',
            );

            final event = events.first;
            expect(
              event['new_plan'],
              equals(input.planType),
              reason: 'Billing event new_plan must match input plan_type',
            );
            expect(
              event['new_max_vehicles'],
              equals(input.maxVehicles),
              reason: 'Billing event new_max_vehicles must match input',
            );
            expect(
              event['new_max_contracts'],
              equals(input.maxContracts),
              reason: 'Billing event new_max_contracts must match input',
            );
            expect(
              event['changed_by_super_admin_id'],
              equals(superAdminUserId),
              reason: 'Billing event must record super_admin_user_id',
            );
          },
        );
      }

      // ── Property 2.3: Service_role bypass works ────────────────────────────
      // When called via service_role (no JWT sub), the function does not throw
      // an exception — it bypasses the super_admin JWT claim check.

      for (final planType in _validPlanTypes) {
        test(
          'P2.3: service_role bypass works for plan=$planType — no exception when JWT sub is null',
          () async {
            final cnpj = _uniqueCnpj();
            final superAdminUserId = _uuid.v4();

            // service_role client has no JWT sub → bypass path
            final rows = await serviceRoleClient.rpc<List<dynamic>>(
              'super_admin_create_organization',
              params: {
                'p_legal_name': 'PBT Bypass Legal',
                'p_trade_name': 'PBT Bypass Corp',
                'p_cnpj': cnpj,
                'p_timezone': 'America/Sao_Paulo',
                'p_currency_code': 'BRL',
                'p_plan_type': planType,
                'p_max_vehicles': 10,
                'p_max_active_contracts': 5,
                'p_super_admin_user_id': superAdminUserId,
                'p_tool_cost_cents': 25000,
                'p_reason': 'PBT service_role bypass test',
              },
            );
            final orgId =
                (rows.first as Map<String, dynamic>)['org_id'] as String;

            // If we get here without exception, bypass worked
            expect(
              orgId,
              isNotEmpty,
              reason: 'Service_role bypass must succeed and return org UUID',
            );
          },
        );
      }

      // ── Property 2.4: allowed_domains normalization ────────────────────────
      // When allowed_domains are updated with mixed-case, spaces, and empty
      // strings, the stored value is normalized (lowercase, trimmed, deduped).
      //
      // NOTE: The text[] overload from 20260504000004 has the is_active bug,
      // so we test normalization via super_admin_update_allowed_domains RPC
      // which shares the same normalization logic and is NOT broken.

      test(
        'P2.4: allowed_domains normalization — '
        'mixed-case, spaces, empty strings are normalized to lowercase/trimmed/deduped',
        () async {
          // First create an org via the working overload
          final cnpj = _uniqueCnpj();
          final superAdminUserId = _uuid.v4();

          final rows = await serviceRoleClient.rpc<List<dynamic>>(
            'super_admin_create_organization',
            params: {
              'p_legal_name': 'PBT Domains Legal',
              'p_trade_name': 'PBT Domains Corp',
              'p_cnpj': cnpj,
              'p_timezone': 'America/Sao_Paulo',
              'p_currency_code': 'BRL',
              'p_plan_type': 'professional',
              'p_max_vehicles': 10,
              'p_max_active_contracts': 5,
              'p_super_admin_user_id': superAdminUserId,
              'p_tool_cost_cents': 50000,
              'p_reason': 'PBT domains normalization test',
            },
          );
          final orgId =
              (rows.first as Map<String, dynamic>)['org_id'] as String;

          // Now update allowed_domains with mixed-case, spaces, empty strings
          await serviceRoleClient.rpc<void>(
            'super_admin_update_allowed_domains',
            params: {
              'p_org_id': orgId,
              'p_allowed_domains': [
                ' Example.COM ',
                'test.io',
                '',
                '  TEST.IO  ',
              ],
              'p_super_admin_user_id': superAdminUserId,
            },
          );

          // Verify normalization
          final org = await serviceRoleClient
              .from('organizations')
              .select('allowed_domains')
              .eq('id', orgId)
              .single();

          final domains = List<String>.from(org['allowed_domains'] as List);

          // Should be lowercase, trimmed, deduplicated, empty removed
          expect(domains, contains('example.com'));
          expect(domains, contains('test.io'));
          expect(
            domains.length,
            equals(2),
            reason: 'Duplicates and empty strings must be removed',
          );
          // No uppercase or spaces
          for (final d in domains) {
            expect(
              d,
              equals(d.toLowerCase().trim()),
              reason: 'All domains must be lowercase and trimmed',
            );
          }
        },
      );

      // ── Concrete example: full org creation flow ───────────────────────────
      // Verifies the complete preservation scenario with specific values.

      test(
        'Concrete: org creation produces correct organizations row and billing event '
        '(mirrors E2E assertions #2 and #3)',
        () async {
          final cnpj = _uniqueCnpj();
          final superAdminUserId = _uuid.v4();

          final rows = await serviceRoleClient.rpc<List<dynamic>>(
            'super_admin_create_organization',
            params: {
              'p_legal_name': 'Preservation Test Transportes Ltda.',
              'p_trade_name': 'Preservation Corp',
              'p_cnpj': cnpj,
              'p_timezone': 'America/Sao_Paulo',
              'p_currency_code': 'BRL',
              'p_plan_type': 'professional',
              'p_max_vehicles': 100,
              'p_max_active_contracts': 20,
              'p_super_admin_user_id': superAdminUserId,
              'p_tool_cost_cents': 50000,
              'p_dwell_time_seconds': 300,
              'p_reason': 'Preservation test reason',
            },
          );
          final orgId =
              (rows.first as Map<String, dynamic>)['org_id'] as String;

          // Assertion #2 equivalent: Org row exists with correct name and plan_type
          final org = await serviceRoleClient
              .from('organizations')
              .select()
              .eq('id', orgId)
              .single();
          expect(org['name'], equals('Preservation Corp'));
          expect(org['plan_type'], equals('professional'));
          expect(org['max_vehicles'], equals(100));
          expect(org['max_active_contracts'], equals(20));
          expect(
            org['legal_name'],
            equals('Preservation Test Transportes Ltda.'),
          );
          expect(org['is_active'], isTrue);

          // Assertion #3 equivalent: Billing event ORG_CREATED exists
          final events = await serviceRoleClient
              .from('tenant_billing_events')
              .select()
              .eq('organization_id', orgId)
              .eq('event_type', 'ORG_CREATED');
          expect(
            events,
            isNotEmpty,
            reason: 'Must have billing event ORG_CREATED',
          );

          final event = events.first;
          expect(event['new_plan'], equals('professional'));
          expect(event['new_max_vehicles'], equals(100));
          expect(event['new_max_contracts'], equals(20));
          expect(event['changed_by_super_admin_id'], equals(superAdminUserId));
        },
      );
    },
  );
}
