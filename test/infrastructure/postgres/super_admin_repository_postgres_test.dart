/// Testes de integração para [SupabaseSuperAdminRepository].
///
/// Requer Supabase local rodando com todas as migrations da Phase 9.2 aplicadas.
/// Execute: `supabase start` antes de rodar estes testes.
///
/// Comando:
///   flutter test test/infrastructure/postgres/super_admin_repository_postgres_test.dart
///
/// Se o Supabase local não estiver rodando, os testes são automaticamente
/// marcados como SKIP (não FAIL) — mesmo comportamento dos outros testes postgres.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/plan_type.dart';
import 'package:veraprob/domain/super_admin/system_audit_log_entry.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_super_admin_repository.dart';

import 'postgres_test_config.dart';

const _uuid = Uuid();

// ── Helpers ───────────────────────────────────────────────────────────────────

CreateOrganizationCommand _testCmd(String cnpj) => CreateOrganizationCommand(
  legalName: 'Integration Test Ltda.',
  tradeName: 'Test Corp ${cnpj.substring(0, 4)}',
  cnpj: cnpj,
  timezone: 'America/Sao_Paulo',
  currencyCode: 'BRL',
  planType: PlanType.starter,
  maxVehicles: 10,
  maxActiveContracts: 5,
  initialAdminEmail: 'admin-${_uuid.v4()}@test.com',
  superAdminUserId: _uuid.v4(),
);

/// Gera um CNPJ de 14 dígitos único por execução de teste.
String _uniqueCnpj() {
  // millis desde epoch (~13 dígitos em 2026). Completa com zeros à esquerda
  // e pega os últimos 14 — garante unicidade sem RangeError.
  final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toString().padLeft(
    14,
    '0',
  );
  return ts.substring(ts.length - 14);
}

Future<String> _ensureUser(
  String email,
  String password, {
  required String supabaseUrl,
  required String serviceRoleKey,
}) async {
  final res = await http.post(
    Uri.parse('$supabaseUrl/auth/v1/admin/users'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
    }),
  );

  if (res.statusCode == 201 || res.statusCode == 200) {
    return jsonDecode(res.body)['id'] as String;
  }
  // Try to find if already exists
  final search = await http.get(
    Uri.parse('$supabaseUrl/auth/v1/admin/users'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
    },
  );

  final decoded = jsonDecode(search.body);
  List users;
  if (decoded is List) {
    users = decoded;
  } else if (decoded is Map && decoded.containsKey('users')) {
    users = decoded['users'] as List;
  } else {
    throw Exception('Unexpected Auth Admin API response: $decoded');
  }

  return users.firstWhere((u) => u['email'] == email)['id'] as String;
}

Future<SupabaseClient> _signIn(
  String email,
  String password, {
  required String supabaseUrl,
  required String anonKey,
}) async {
  final client = SupabaseClient(supabaseUrl, anonKey);
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'SupabaseSuperAdminRepository — Integração Postgres',
    skip: !isRunning
        ? 'Supabase local não está rodando. Execute: supabase start'
        : null,
    () {
      // Integration tests use service_role client to bypass RLS for test setup.
      // The repository takes a single authenticated client (Phase 9.6 refactor).
      late SupabaseClient serviceRoleClient;
      late SupabaseClient superAdminClient;
      late SupabaseSuperAdminRepository repo;
      late SupabaseSuperAdminRepository superAdminRepo;

      setUpAll(() async {
        // Inicializa Supabase.instance (SharedPreferences mock, auth) —
        // necessário para algumas operações internas do SDK.
        await PostgresTestConfig.createClient();

        serviceRoleClient = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );

        // 1. Ensure SuperAdmin user exists in Auth and public.super_admin_users
        const email = 'super_admin_test@veraprob.com';
        const password = 'SuperPassword123!';
        final superAdminId = await _ensureUser(
          email,
          password,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          serviceRoleKey: PostgresTestConfig.serviceRoleKey,
        );

        // 2. Force super_admin=true metadata (INV-14 enforcement in Deno)
        await http.put(
          Uri.parse(
            '${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users/$superAdminId',
          ),
          headers: {
            'apikey': PostgresTestConfig.serviceRoleKey,
            'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'app_metadata': {'super_admin': true},
          }),
        );

        // 3. Ensure organization record for super_admin_users table (if needed)
        await serviceRoleClient.from('super_admin_users').upsert({
          'user_id': superAdminId,
          'email': email,
        }, onConflict: 'user_id');

        // 4. Sign in to get valid JWT for proxy calls
        superAdminClient = await _signIn(
          email,
          password,
          supabaseUrl: PostgresTestConfig.supabaseUrl,
          anonKey: PostgresTestConfig.supabaseAnonKey,
        );

        repo = SupabaseSuperAdminRepository(serviceRoleClient);
        superAdminRepo = SupabaseSuperAdminRepository(superAdminClient);
      });

      tearDownAll(() async {
        await serviceRoleClient.dispose();
        await superAdminClient.dispose();
      });

      // ── createOrganization ─────────────────────────────────────────────────

      group('createOrganization', () {
        test('insere organização e retorna UUID válido', () async {
          final cnpj = _uniqueCnpj();
          final orgId = await repo.createOrganization(_testCmd(cnpj));

          expect(orgId, isNotEmpty);
          // UUID v4 format
          expect(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
              caseSensitive: false,
            ).hasMatch(orgId),
            isTrue,
            reason: 'Deve retornar UUID v4',
          );

          // Verificar linha no banco
          final row = await serviceRoleClient
              .from('organizations')
              .select()
              .eq('id', orgId)
              .single();

          expect(row['plan_type'], equals('starter'));
          expect(row['max_vehicles'], equals(10));
          expect(row['max_active_contracts'], equals(5));
          expect(row['is_active'], isTrue);
        });

        test(
          'registra billing event com event_type ORG_CREATED (INV-1)',
          () async {
            final cnpj = _uniqueCnpj();
            final orgId = await repo.createOrganization(_testCmd(cnpj));

            final events = await serviceRoleClient
                .from('tenant_billing_events')
                .select()
                .eq('organization_id', orgId)
                .eq('event_type', 'ORG_CREATED');

            expect(events, isNotEmpty, reason: 'Deve ter pelo menos um evento');
            final event = events.first;
            expect(event['new_plan'], equals('starter'));
            expect(event['new_max_vehicles'], equals(10));
            expect(event['new_max_contracts'], equals(5));
          },
        );

        test('rejeita CNPJ duplicado (R2: unique index uq_org_cnpj)', () async {
          final cnpj = _uniqueCnpj();
          await repo.createOrganization(_testCmd(cnpj)); // primeiro insert

          // Segundo insert com mesmo CNPJ deve lançar exceção do Postgres
          await expectLater(
            repo.createOrganization(_testCmd(cnpj)),
            throwsException,
          );
        });

        test(
          'billing event é imutável — UPDATE é bloqueado por trigger (INV-1)',
          () async {
            final cnpj = _uniqueCnpj();
            final orgId = await repo.createOrganization(_testCmd(cnpj));

            final events = await serviceRoleClient
                .from('tenant_billing_events')
                .select('id')
                .eq('organization_id', orgId);
            final eventId = (events.first as Map)['id'] as String;

            // Tentativa de UPDATE deve ser bloqueada pelo trigger
            await expectLater(
              serviceRoleClient
                  .from('tenant_billing_events')
                  .update({'reason': 'tentativa de adulteração'})
                  .eq('id', eventId),
              throwsException,
            );
          },
        );
      });

      // ── updateOrganizationQuota ────────────────────────────────────────────

      group('updateOrganizationQuota', () {
        test('updates plan_type and quotas on existing org', () async {
          final cnpj = _uniqueCnpj();
          final superAdminId = _uuid.v4();
          final orgId = await repo.createOrganization(
            CreateOrganizationCommand(
              legalName: 'Quota Test Ltda.',
              tradeName: 'QuotaCo',
              cnpj: cnpj,
              timezone: 'America/Sao_Paulo',
              currencyCode: 'BRL',
              planType: PlanType.starter,
              maxVehicles: 10,
              maxActiveContracts: 5,
              initialAdminEmail: 'admin-${_uuid.v4()}@test.com',
              superAdminUserId: superAdminId,
            ),
          );

          await repo.updateOrganizationQuota(
            UpdateOrganizationQuotaCommand(
              organizationId: orgId,
              newPlanType: 'professional',
              newMaxVehicles: 100,
              newMaxActiveContracts: 50,
              superAdminUserId: superAdminId,
              reason: 'Upgrade for integration test',
            ),
          );

          final row = await serviceRoleClient
              .from('organizations')
              .select('plan_type, max_vehicles, max_active_contracts')
              .eq('id', orgId)
              .single();

          expect(row['plan_type'], equals('professional'));
          expect(row['max_vehicles'], equals(100));
          expect(row['max_active_contracts'], equals(50));
        });

        test('records PLAN_CHANGED billing event (INV-7)', () async {
          final cnpj = _uniqueCnpj();
          final superAdminId = _uuid.v4();
          final orgId = await repo.createOrganization(
            CreateOrganizationCommand(
              legalName: 'Event Test Ltda.',
              tradeName: 'EventCo',
              cnpj: cnpj,
              timezone: 'America/Sao_Paulo',
              currencyCode: 'BRL',
              planType: PlanType.starter,
              maxVehicles: 10,
              maxActiveContracts: 5,
              initialAdminEmail: 'admin-${_uuid.v4()}@test.com',
              superAdminUserId: superAdminId,
            ),
          );

          await repo.updateOrganizationQuota(
            UpdateOrganizationQuotaCommand(
              organizationId: orgId,
              newPlanType: 'enterprise',
              newMaxVehicles: null,
              newMaxActiveContracts: null,
              superAdminUserId: superAdminId,
            ),
          );

          final events = await serviceRoleClient
              .from('tenant_billing_events')
              .select()
              .eq('organization_id', orgId)
              .eq('event_type', 'PLAN_CHANGED');

          expect(events, isNotEmpty);
          final ev = events.first as Map;
          expect(ev['old_plan'], equals('starter'));
          expect(ev['new_plan'], equals('enterprise'));
          expect(ev['changed_by_super_admin_id'], equals(superAdminId));
        });

        test('PLAN_CHANGED billing event is immutable (INV-7)', () async {
          final cnpj = _uniqueCnpj();
          final superAdminId = _uuid.v4();
          final orgId = await repo.createOrganization(
            CreateOrganizationCommand(
              legalName: 'Immutable Test Ltda.',
              tradeName: 'ImmutCo',
              cnpj: cnpj,
              timezone: 'America/Sao_Paulo',
              currencyCode: 'BRL',
              planType: PlanType.starter,
              maxVehicles: 5,
              maxActiveContracts: 2,
              initialAdminEmail: 'admin-${_uuid.v4()}@test.com',
              superAdminUserId: superAdminId,
            ),
          );

          await repo.updateOrganizationQuota(
            UpdateOrganizationQuotaCommand(
              organizationId: orgId,
              newPlanType: 'professional',
              newMaxVehicles: 50,
              newMaxActiveContracts: 20,
              superAdminUserId: superAdminId,
            ),
          );

          final events = await serviceRoleClient
              .from('tenant_billing_events')
              .select('id')
              .eq('organization_id', orgId)
              .eq('event_type', 'PLAN_CHANGED');
          final eventId = (events.first as Map)['id'] as String;

          await expectLater(
            serviceRoleClient
                .from('tenant_billing_events')
                .update({'reason': 'tampered'})
                .eq('id', eventId),
            throwsException,
          );
        });
      });

      // ── Hard quota triggers — P0001 ────────────────────────────────────────

      group('Hard quota triggers — P0001', () {
        test('vehicle insert blocked when vehicle quota exceeded', () async {
          final cnpj = _uniqueCnpj();
          final superAdminId = _uuid.v4();
          final orgId = await repo.createOrganization(
            CreateOrganizationCommand(
              legalName: 'Quota Veh Test Ltda.',
              tradeName: 'VehQuotaCo',
              cnpj: cnpj,
              timezone: 'America/Sao_Paulo',
              currencyCode: 'BRL',
              planType: PlanType.starter,
              maxVehicles: 1,
              maxActiveContracts: 5,
              initialAdminEmail: 'admin-${_uuid.v4()}@test.com',
              superAdminUserId: superAdminId,
            ),
          );

          // Insert first vehicle — should succeed
          await serviceRoleClient.from('vehicles').insert({
            'id': _uuid.v4(),
            'organization_id': orgId,
            'plate':
                'TST${DateTime.now().toUtc().millisecondsSinceEpoch % 9000 + 1000}',
            'status': 'available',
          });

          // Second vehicle should be blocked by quota trigger (P0001)
          await expectLater(
            serviceRoleClient.from('vehicles').insert({
              'id': _uuid.v4(),
              'organization_id': orgId,
              'plate':
                  'BLK${DateTime.now().toUtc().millisecondsSinceEpoch % 9000 + 1000}',
              'status': 'available',
            }),
            throwsException,
          );
        });

        test(
          'contract insert blocked when active contract quota exceeded',
          () async {
            final cnpj = _uniqueCnpj();
            final superAdminId = _uuid.v4();
            final orgId = await repo.createOrganization(
              CreateOrganizationCommand(
                legalName: 'Quota Ctr Test Ltda.',
                tradeName: 'CtrQuotaCo',
                cnpj: cnpj,
                timezone: 'America/Sao_Paulo',
                currencyCode: 'BRL',
                planType: PlanType.starter,
                maxVehicles: 10,
                maxActiveContracts: 1,
                initialAdminEmail: 'admin-${_uuid.v4()}@test.com',
                superAdminUserId: superAdminId,
              ),
            );

            // Insert first active contract — should succeed
            await serviceRoleClient.from('contracts').insert({
              'id': _uuid.v4(),
              'organization_id': orgId,
              'name': 'Contrato 1',
              'contractor_name': 'Transp. A',
              'status': 'active',
              'valid_from_utc': '2026-01-01T00:00:00Z',
              'valid_until_utc': '2026-12-31T23:59:59Z',
            });

            // Second active contract should be blocked (P0001)
            await expectLater(
              serviceRoleClient.from('contracts').insert({
                'id': _uuid.v4(),
                'organization_id': orgId,
                'name': 'Contrato 2',
                'contractor_name': 'Transp. B',
                'status': 'active',
                'valid_from_utc': '2026-01-01T00:00:00Z',
                'valid_until_utc': '2026-12-31T23:59:59Z',
              }),
              throwsException,
            );
          },
        );
      });

      // ── getAllTenantHealth ──────────────────────────────────────────────────
      // NOTE (Phase 9.6): These tests require the `super-admin-proxy` Edge
      // Function to be deployed (`supabase functions serve super-admin-proxy`).
      // They are skipped here because they depend on the Edge Function runtime,
      // not just the DB. Unit-level coverage is in
      // test/infrastructure/super_admin/supabase_super_admin_repository_test.dart

      group('getAllTenantHealth', () {
        test('retorna lista de TenantHealthSnapshot', () async {
          // Cria uma org de teste para garantir que a view tenha pelo menos uma linha
          final cnpj = _uniqueCnpj();
          await repo.createOrganization(_testCmd(cnpj));

          final snapshots = await superAdminRepo.getAllTenantHealth();

          expect(snapshots, isA<List<TenantHealthSnapshot>>());
          expect(snapshots, isNotEmpty);

          for (final s in snapshots) {
            expect(s.id, isNotEmpty);
            expect(s.name, isNotEmpty);
          }
        });

        test(
          'org recém-criada aparece na view com active_contract_count = 0',
          () async {
            final cnpj = _uniqueCnpj();
            final orgId = await repo.createOrganization(_testCmd(cnpj));

            final snapshots = await superAdminRepo.getAllTenantHealth();
            final match = snapshots.where((s) => s.id == orgId).toList();

            expect(
              match,
              isNotEmpty,
              reason: 'Org recém-criada deve aparecer na health view',
            );
            expect(match.first.activeContractCount, equals(0));
            expect(match.first.openCriticalAlertCount, equals(0));
          },
        );
      });

      // ── getSystemAuditLog ──────────────────────────────────────────────────
      // NOTE (Phase 9.6): Same Edge Function requirement as getAllTenantHealth.

      group('getSystemAuditLog', () {
        test('retorna lista sem filtro', () async {
          final logs = await superAdminRepo.getSystemAuditLog(limit: 10);
          expect(logs, isA<List<SystemAuditLogEntry>>());
        });

        test('filtra por organization_id corretamente', () async {
          final cnpj = _uniqueCnpj();
          final orgId = await repo.createOrganization(_testCmd(cnpj));

          // Insere entrada de log vinculada à org de teste
          await serviceRoleClient.from('system_audit_log').insert({
            'event_type': 'SUPER_ADMIN_TEST',
            'severity': 'info',
            'organization_id': orgId,
            'source': 'test_suite',
          });

          final filtered = await superAdminRepo.getSystemAuditLog(
            organizationId: orgId,
            limit: 50,
          );

          expect(filtered, isNotEmpty);
          expect(
            filtered.every((e) => e.organizationId == orgId),
            isTrue,
            reason: 'Todos os logs filtrados devem pertencer à org',
          );
        });

        test('filtra por severity corretamente', () async {
          final logs = await superAdminRepo.getSystemAuditLog(
            severity: 'error',
            limit: 20,
          );
          expect(logs.every((e) => e.severity == 'error'), isTrue);
        });
      });
    },
  );
}
