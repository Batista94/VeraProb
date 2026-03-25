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

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/system_audit_log_entry.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
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
  planType: 'starter',
  maxVehicles: 10,
  maxActiveContracts: 5,
  initialAdminEmail: 'admin-${_uuid.v4()}@test.com',
  superAdminUserId: _uuid.v4(),
);

/// Gera um CNPJ de 14 dígitos único por execução de teste.
String _uniqueCnpj() {
  // millis desde epoch (~13 dígitos em 2026). Completa com zeros à esquerda
  // e pega os últimos 14 — garante unicidade sem RangeError.
  final ts = DateTime.now().millisecondsSinceEpoch.toString().padLeft(14, '0');
  return ts.substring(ts.length - 14);
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
      // D3: client separado com service_role, sem Supabase.initialize() duplo.
      // PostgresTestConfig.serviceRoleKey é o sb_secret_ do ambiente local.
      late SupabaseClient serviceRoleClient;
      late SupabaseSuperAdminRepository repo;

      setUpAll(() async {
        // Inicializa Supabase.instance (SharedPreferences mock, auth) —
        // necessário para algumas operações internas do SDK.
        await PostgresTestConfig.createClient();

        // Client de service_role separado para o repositório SuperAdmin (D3).
        serviceRoleClient = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );
        repo = SupabaseSuperAdminRepository(
          serviceRoleClient,
          serviceRoleClient,
        );
      });

      tearDownAll(() async {
        await serviceRoleClient.dispose();
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

      // ── getAllTenantHealth ──────────────────────────────────────────────────

      group('getAllTenantHealth', () {
        test('retorna lista de TenantHealthSnapshot', () async {
          // Cria uma org de teste para garantir que a view tenha pelo menos uma linha
          final cnpj = _uniqueCnpj();
          await repo.createOrganization(_testCmd(cnpj));

          final snapshots = await repo.getAllTenantHealth();

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

            final snapshots = await repo.getAllTenantHealth();
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

      group('getSystemAuditLog', () {
        test('retorna lista sem filtro', () async {
          final logs = await repo.getSystemAuditLog(limit: 10);
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

          final filtered = await repo.getSystemAuditLog(
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
          final logs = await repo.getSystemAuditLog(
            severity: 'error',
            limit: 20,
          );
          expect(logs.every((e) => e.severity == 'error'), isTrue);
        });
      });
    },
  );
}
