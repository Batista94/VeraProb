// Integration tests for PostgresOperationalAlertRepository.
//
// Requires: `supabase start` running locally on 127.0.0.1:54321.
// Run: flutter test test/infrastructure/sla_audit/postgres_operational_alert_repository_test.dart
//
// Invariants:
//   INV-1  — Tenant Sovereignty (organization_id isolation)
//   INV-5  — RLS Authority (auth.jwt() ->> 'organization_id')
//   INV-10 — JWT Claim Canonicality
//   INV-22 — Multi-Tenant isolation (cross-org NEVER leaks)
//   INV-26 — Error Parity (DB codes never reach caller)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_operational_alert_repository.dart';

import '../postgres/postgres_test_config.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _uuid = Uuid();
const _testPassword = 'TestPassword123!';

// Randomised per-run to avoid FK/UNIQUE collisions between runs.
final _orgAId = _uuid.v4();
final _orgBId = _uuid.v4();
final _userAEmail = 'alert_a_${_uuid.v4().substring(0, 8)}@veraprob.test';
final _userBEmail = 'alert_b_${_uuid.v4().substring(0, 8)}@veraprob.test';

// Shared entity/contract IDs seeded once in setUpAll.
final _entityId = _uuid.v4();
late String _orgAContractId;
late String _orgBContractId;
late String _traceIdA; // Seeded trace for FK-safe alert tests

// ── Auth helpers ─────────────────────────────────────────────────────────────

Future<String> _ensureUser(String email, {required String orgId}) async {
  final res = await http.post(
    Uri.parse('${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users'),
    headers: {
      'apikey': PostgresTestConfig.serviceRoleKey,
      'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': _testPassword,
      'email_confirm': true,
      'app_metadata': {'org_id': orgId},
    }),
  );
  if (res.statusCode == 200 || res.statusCode == 201) {
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }
  if (res.statusCode == 422) {
    final list = await http.get(
      Uri.parse(
        '${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users?email=$email',
      ),
      headers: {
        'apikey': PostgresTestConfig.serviceRoleKey,
        'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
      },
    );
    final users =
        ((jsonDecode(list.body) as Map<String, dynamic>)['users'] as List);
    final userId = (users.first as Map<String, dynamic>)['id'] as String;

    // Ensure app_metadata.org_id is set (may be missing from a prior run).
    await http.put(
      Uri.parse(
        '${PostgresTestConfig.supabaseUrl}/auth/v1/admin/users/$userId',
      ),
      headers: {
        'apikey': PostgresTestConfig.serviceRoleKey,
        'Authorization': 'Bearer ${PostgresTestConfig.serviceRoleKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'app_metadata': {'org_id': orgId},
      }),
    );
    return userId;
  }
  throw Exception('Failed to create user $email: ${res.body}');
}

Future<SupabaseClient> _signIn(String email) async {
  final client = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.supabaseAnonKey,
  );
  await client.auth.signInWithPassword(email: email, password: _testPassword);
  return client;
}

/// Seeds a contract via service_role; returns the contract UUID.
Future<String> _seedContract(SupabaseClient admin, String orgId) async {
  final id = _uuid.v4();
  await admin.from('contracts').insert({
    'id': id,
    'organization_id': orgId,
    'name': 'Alert Test Contract',
    'contractor_name': 'Alert Test Contractor',
    'status': 'draft',
    'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
    'valid_until_utc': DateTime.now()
        .toUtc()
        .add(const Duration(days: 90))
        .toIso8601String(),
  });
  return id;
}

/// Builds a minimal [OperationalAlert] for the given org/contract.
OperationalAlert _buildAlert({
  required String orgId,
  required String contractId,
  String severity = 'CRITICAL',
  String status = 'ACTIVE',
  String? id,
  Map<String, dynamic> context = const {},
  String? triggeringEventId,
  String? traceId,
}) {
  final effectiveContext = Map<String, dynamic>.from(context);
  if (!effectiveContext.containsKey('driver_id')) {
    effectiveContext['driver_id'] = _uuid.v4();
  }
  return OperationalAlert(
    id: id ?? _uuid.v4(),
    organizationId: orgId,
    entityId: _entityId,
    contractId: contractId,
    alertType: 'SLA_BREACH',
    severity: severity,
    triggeredAtUtc: DateTime.now().toUtc(),
    triggeringEventId: triggeringEventId,
    traceId: traceId,
    context: effectiveContext,
    status: status,
  );
}

// ── Main ─────────────────────────────────────────────────────────────────────

void main() {
  group('PostgresOperationalAlertRepository — Integration', () {
    late SupabaseClient adminClient;
    late SupabaseClient orgAClient;
    late SupabaseClient orgBClient;
    late PostgresOperationalAlertRepository repoA;

    setUpAll(() async {
      final isRunning = await PostgresTestConfig.isSupabaseRunning();
      if (!isRunning) {
        return; // tests will be individually skipped via `skip` below
      }

      adminClient = PostgresTestConfig.createServiceRoleClient();

      // Provision orgs
      await PostgresTestConfig.ensureSentinelOrg(
        id: _orgAId,
        name: 'Alert Test Org A',
      );
      await PostgresTestConfig.ensureSentinelOrg(
        id: _orgBId,
        name: 'Alert Test Org B',
      );

      // Provision contracts
      _orgAContractId = await _seedContract(adminClient, _orgAId);
      _orgBContractId = await _seedContract(adminClient, _orgBId);

      // Provision a contractual_evaluation_trace for FK-safe alert tests
      _traceIdA = _uuid.v4();
      await adminClient.from('contractual_evaluation_traces').insert({
        'id': _traceIdA,
        'organization_id': _orgAId,
        'entity_id': _entityId,
        'triggering_event_id': _uuid.v4(),
        'engine_version': 'test-v1',
      });

      // Provision auth users + roles
      final userAId = await _ensureUser(_userAEmail, orgId: _orgAId);
      final userBId = await _ensureUser(_userBEmail, orgId: _orgBId);

      await adminClient.from('user_roles').upsert({
        'user_id': userAId,
        'organization_id': _orgAId,
        'role': 'TENANT_ADMIN',
      }, onConflict: 'user_id');
      await adminClient.from('user_roles').upsert({
        'user_id': userBId,
        'organization_id': _orgBId,
        'role': 'TENANT_ADMIN',
      }, onConflict: 'user_id');

      // Authenticate
      orgAClient = await _signIn(_userAEmail);
      orgBClient = await _signIn(_userBEmail);

      repoA = PostgresOperationalAlertRepository(orgAClient);
    });

    tearDownAll(() async {
      try {
        await PostgresTestConfig.cleanupOperationalAlerts(
          orgIds: [_orgAId, _orgBId],
        );
        await adminClient
            .from('contractual_evaluation_traces')
            .delete()
            .inFilter('organization_id', [_orgAId, _orgBId]);
        await adminClient.from('contracts').delete().inFilter(
          'organization_id',
          [_orgAId, _orgBId],
        );
      } catch (_) {
        // Supabase offline — cleanup skipped. Tests were already skipped.
      }
      try {
        await orgAClient.auth.signOut();
        await orgBClient.auth.signOut();
        await adminClient.dispose();
      } catch (_) {
        // Ignore sign-out failures when offline.
      }
    });

    // ── GRUPO A: Segurança de Tenant (Adversarial) ──────────────────────

    group('GRUPO A — Tenant Sovereignty (Adversarial)', () {
      test(
        'ALERT-A1 [INV-22]: findById de alerta de Org_B retorna null para Org_A',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          // Plant Org_B alert via service_role (adversarial seed).
          final alertBId = await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgBId,
            entityId: _entityId,
            contractId: _orgBContractId,
            severity: 'WARNING',
          );

          // Org_A client attempts to read Org_B alert.
          final result = await repoA.findById(
            alertBId,
            organizationId: _orgAId,
          );

          if (result != null) {
            debugPrint(
              '[FORENSE ALERT-A1] TENTATIVA DE ACESSO ILEGAL DETECTADA E '
              'PERMITIDA PELO BANCO — FALHA GRAVE (INV-22). '
              'alertId=$alertBId orgBId=$_orgBId',
            );
          }

          expect(
            result,
            isNull,
            reason:
                'INV-22: RLS deve impedir Org_A de ler alerta de Org_B. '
                'findById deve retornar null (não lançar exceção — Oracle Attack prevention).',
          );
        },
      );

      test(
        'ALERT-A2 [INV-22]: findActive de Org_A não vaza nenhum alerta de Org_B (1.000 alertas)',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          // Seed 3 known alerts for Org_A.
          await PostgresTestConfig.seedOperationalAlertBatch(
            orgId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
            count: 3,
          );

          // Seed 1.000 alerts for Org_B (adversarial volume).
          await PostgresTestConfig.seedOperationalAlertBatch(
            orgId: _orgBId,
            entityId: _entityId,
            contractId: _orgBContractId,
            count: 1000,
          );

          final results = await repoA.findActive(_orgAId);

          final leaked = results
              .where((a) => a.organizationId == _orgBId)
              .toList();
          if (leaked.isNotEmpty) {
            debugPrint(
              '[FORENSE ALERT-A2] VAZAMENTO DE ISOLAMENTO — '
              '${leaked.length} alerta(s) de Org_B visíveis para Org_A — '
              'FALHA GRAVE (INV-22).',
            );
          }

          expect(
            leaked,
            isEmpty,
            reason:
                'INV-22: findActive deve retornar zero alertas de Org_B, '
                'mesmo com 1.000 registros adversariais presentes.',
          );
          expect(
            results.every((a) => a.organizationId == _orgAId),
            isTrue,
            reason: 'Todos os alertas retornados devem pertencer a Org_A.',
          );
        },
      );

      test(
        'ALERT-A3 [INV-22, INV-5]: update de alerta de Org_B com token de Org_A não altera dados',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          // Plant Org_B alert.
          final alertBId = await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgBId,
            entityId: _entityId,
            contractId: _orgBContractId,
            status: 'ACTIVE',
          );

          // Org_A attempts to update Org_B alert (cross-org write attack).
          final attackPayload = OperationalAlert(
            id: alertBId,
            organizationId: _orgBId,
            entityId: _entityId,
            contractId: _orgBContractId,
            alertType: 'SLA_BREACH',
            severity: 'CRITICAL',
            triggeredAtUtc: DateTime.now().toUtc(),
            status: 'ACKNOWLEDGED',
            acknowledgedAtUtc: DateTime.now().toUtc(),
            acknowledgedByUserId: 'attacker-user',
            context: {'driver_id': _uuid.v4()},
          );

          // The repository has Defense-in-Depth (.eq organization_id) AND
          // the DB has RLS. Either gate should block this silently (0 rows).
          await repoA.update(attackPayload);

          // Verify via service_role that the original record is unchanged.
          final adminRepo = PostgresOperationalAlertRepository(adminClient);
          final original = await adminRepo.findById(
            alertBId,
            organizationId: _orgBId,
          );

          if (original?.status == 'ACKNOWLEDGED') {
            debugPrint(
              '[FORENSE ALERT-A3] ATAQUE DE ESCRITA CROSS-ORG ACEITO PELO BANCO — '
              'alerta de Org_B foi modificado por token de Org_A — '
              'FALHA CRÍTICA (INV-22, INV-5).',
            );
          }

          expect(
            original?.status,
            equals('ACTIVE'),
            reason:
                'INV-22: RLS + Defense-in-Depth devem bloquear update '
                'cross-org. O status de Org_B deve permanecer ACTIVE.',
          );
        },
      );
    });

    // ── GRUPO B: Fluxo Operacional ──────────────────────────────────────

    group('GRUPO B — Fluxo Operacional (Happy Path & Edge Cases)', () {
      test(
        'ALERT-B1 [INV-15]: persist/retrieve com JSON 5 níveis + UTF-8 íntegros',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          final complexContext = {
            'emoji': '🚨🔴⚠️',
            'acentos': 'ônibus, ação, São Paulo',
            'nivel1': {
              'nivel2': {
                'nivel3': {
                  'nivel4': {
                    'nivel5': {'valor': 'profundo', 'num': 42},
                  },
                },
              },
            },
            'lista': [1, 2, 3, 'texto', true, null],
            'unicode': '\u4e2d\u6587\u6d4b\u8bd5',
          };

          final alert = _buildAlert(
            orgId: _orgAId,
            contractId: _orgAContractId,
            context: complexContext,
            traceId: _traceIdA,
            triggeringEventId: _uuid.v4(),
          );

          final savedId = await repoA.save(alert);
          final retrieved = await repoA.findById(
            savedId,
            organizationId: _orgAId,
          );

          expect(retrieved, isNotNull);
          expect(retrieved!.context['emoji'], equals('🚨🔴⚠️'));
          expect(
            retrieved.context['acentos'],
            equals('ônibus, ação, São Paulo'),
          );
          expect(
            (retrieved.context['nivel1'] as Map)['nivel2'] != null,
            isTrue,
            reason: 'JSON 5 níveis deve preservar estrutura no roundtrip.',
          );
          expect(retrieved.traceId, equals(alert.traceId));
          expect(retrieved.triggeringEventId, equals(alert.triggeringEventId));
        },
      );

      test(
        'ALERT-B2 [INV-26]: severity desconhecida no DB não quebra desserialização da lista',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          // Seed an alert with unknown severity via service_role (simulates
          // future enum value or data migration artifact).
          await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
            severity: 'UNKNOWN_FUTURE_VALUE',
          );
          // Seed two normal alerts.
          await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
            severity: 'WARNING',
          );
          await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
            severity: 'INFO',
          );

          // findActive must not throw — resilience is the invariant.
          final List<OperationalAlert> results;
          try {
            results = await repoA.findActive(_orgAId);
          } catch (e) {
            fail(
              'INV-26: findActive lançou exceção com severity desconhecida: $e. '
              'O repositório deve ser resiliente a valores de enum futuros.',
            );
          }

          final unknownSeverityAlert = results
              .where((a) => a.severity == 'UNKNOWN_FUTURE_VALUE')
              .toList();
          expect(
            unknownSeverityAlert,
            isNotEmpty,
            reason:
                'Alerta com severity desconhecida deve constar na lista '
                '(passthrough sem crash).',
          );
        },
      );

      test(
        'ALERT-B3: campos opcionais null são hidratados corretamente (schema resilience)',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          // Alert with all optional fields null.
          final alert = _buildAlert(
            orgId: _orgAId,
            contractId: _orgAContractId,
          );
          final savedId = await repoA.save(alert);
          final retrieved = await repoA.findById(
            savedId,
            organizationId: _orgAId,
          );

          expect(retrieved, isNotNull);
          expect(retrieved!.triggeringEventId, isNull);
          expect(retrieved.traceId, isNull);
          expect(retrieved.acknowledgedAtUtc, isNull);
          expect(retrieved.acknowledgedByUserId, isNull);
          expect(retrieved.resolvedAtUtc, isNull);
          expect(retrieved.viewedByUserIds, isEmpty);
        },
      );

      test(
        'ALERT-B4: findActive filtra ACTIVE vs RESOLVED corretamente',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          // Seed an ACTIVE and a RESOLVED alert.
          await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
            status: 'ACTIVE',
          );
          await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
            status: 'RESOLVED',
          );

          final results = await repoA.findActive(_orgAId);

          expect(
            results.any((a) => a.status == 'RESOLVED'),
            isFalse,
            reason: 'findActive não deve retornar alertas com status RESOLVED.',
          );
          expect(results.every((a) => a.status == 'ACTIVE'), isTrue);
        },
      );

      test(
        'ALERT-B5: markViewed é idempotente — double-call não duplica userId',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          final alertId = await PostgresTestConfig.seedOperationalAlert(
            orgId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
          );
          const userId = '00000000-0000-0000-0000-000000000099';

          // Call markViewed twice with the same userId.
          await repoA.markViewed(alertId, userId);
          await repoA.markViewed(alertId, userId);

          final retrieved = await repoA.findById(
            alertId,
            organizationId: _orgAId,
          );
          expect(retrieved, isNotNull);

          final viewedIds = retrieved!.viewedByUserIds;
          final occurrences = viewedIds.where((id) => id == userId).length;
          expect(
            occurrences,
            equals(1),
            reason:
                'markViewed deve ser idempotente — userId não deve ser '
                'duplicado no array viewed_by_user_ids.',
          );
        },
      );

      test(
        'ALERT-B6: save retorna UUID válido; findById confirma todos os campos (roundtrip)',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          final now = DateTime.now().toUtc();
          final alert = OperationalAlert(
            id: _uuid.v4(),
            organizationId: _orgAId,
            entityId: _entityId,
            contractId: _orgAContractId,
            alertType: 'DEVIATION',
            severity: 'WARNING',
            triggeredAtUtc: now,
            triggeringEventId: _uuid.v4(),
            traceId: _traceIdA,
            context: {'key': 'value', 'driver_id': _uuid.v4()},
            status: 'ACTIVE',
          );

          final savedId = await repoA.save(alert);
          expect(savedId, isNotEmpty);

          final retrieved = await repoA.findById(
            savedId,
            organizationId: _orgAId,
          );
          expect(retrieved, isNotNull);
          expect(retrieved!.organizationId, equals(_orgAId));
          expect(retrieved.entityId, equals(_entityId));
          expect(retrieved.contractId, equals(_orgAContractId));
          expect(retrieved.alertType, equals('DEVIATION'));
          expect(retrieved.severity, equals('WARNING'));
          expect(retrieved.status, equals('ACTIVE'));
          expect(retrieved.triggeringEventId, equals(alert.triggeringEventId));
          expect(retrieved.traceId, equals(alert.traceId));
          expect(retrieved.context['key'], equals('value'));
        },
      );
    });

    // ── GRUPO C: Blindagem de Infraestrutura ────────────────────────────

    group('GRUPO C — Blindagem de Infraestrutura', () {
      test(
        'ALERT-C1 [Stress]: 100 INSERTs concorrentes sem deadlock; tempo total < 10s',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          final alerts = List.generate(
            100,
            (_) => _buildAlert(
              orgId: _orgAId,
              contractId: _orgAContractId,
              severity: 'CRITICAL',
            ),
          );

          final stopwatch = Stopwatch()..start();

          // Fire all 100 inserts concurrently.
          final futures = alerts.map(
            (a) => repoA
                .save(a)
                .then<String?>(
                  (id) => null, // success → null marker
                  onError: (Object e) => e.toString(), // failure → error string
                ),
          );
          final results = await Future.wait(futures);

          stopwatch.stop();

          final errors = results.where((r) => r != null).length;
          final elapsed = stopwatch.elapsedMilliseconds;

          expect(
            errors,
            equals(0),
            reason:
                'Alert Storm: nenhum dos 100 INSERTs concorrentes deve falhar '
                '(deadlock ou timeout).',
          );
          expect(
            elapsed,
            lessThan(10000),
            reason:
                'Alert Storm: 100 INSERTs concorrentes devem completar em < 10s. '
                'Tempo atual: ${elapsed}ms. Se falhar, investigar pool de conexões '
                'ou ausência de índice em organization_id.',
          );

          debugPrint(
            '[ALERT-C1] Alert Storm concluído: 100 alertas em ${elapsed}ms '
            '(~${elapsed / 100}ms por alerta).',
          );
        },
      );

      test(
        'ALERT-C2 [RLS Enabled]: row_security está ATIVO em operational_alerts',
        () async {
          final isRunning = await PostgresTestConfig.isSupabaseRunning();
          if (!isRunning) {
            markTestSkipped('Supabase não está rodando');
            return;
          }

          // Query pg_class via service_role to check relrowsecurity flag.
          final result = await adminClient.rpc<dynamic>(
            'check_rls_enabled',
            params: {'p_table_name': 'operational_alerts'},
          );

          // Fallback: query pg_class directly if RPC doesn't exist.
          bool rlsEnabled;
          if (result == null) {
            // Direct pg_class query via raw SQL (requires pg_catalog access).
            final rows = await adminClient
                .from('pg_class')
                .select('relrowsecurity')
                .eq('relname', 'operational_alerts')
                .limit(1);

            if (rows.isEmpty) {
              // pg_class not directly queryable via PostgREST; use metadata approach.
              // Validate indirectly: anon client without auth should see nothing.
              final anonClient = SupabaseClient(
                PostgresTestConfig.supabaseUrl,
                PostgresTestConfig.supabaseAnonKey,
              );
              try {
                final anonResult = await anonClient
                    .from('operational_alerts')
                    .select('id')
                    .limit(1);
                rlsEnabled = anonResult.isEmpty;
              } finally {
                await anonClient.dispose();
              }
            } else {
              rlsEnabled = (rows.first['relrowsecurity'] as bool? ?? false);
            }
          } else {
            rlsEnabled = (result as bool?) ?? false;
          }

          if (!rlsEnabled) {
            debugPrint(
              '[FORENSE ALERT-C2] RLS DESABILITADO EM operational_alerts — '
              'VIOLAÇÃO CRÍTICA INV-1. Qualquer usuário autenticado pode '
              'ler/escrever alertas de qualquer tenant sem restrição.',
            );
          }

          expect(
            rlsEnabled,
            isTrue,
            reason:
                'INV-1: Row Level Security deve estar ATIVO em operational_alerts. '
                'RLS desabilitado expõe todos os alertas a qualquer tenant autenticado.',
          );
        },
      );
    });
  });
}
