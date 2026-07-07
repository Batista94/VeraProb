/// E2E: SuperAdmin cria novo tenant via fluxo completo do handler.
///
/// Mede wall-clock — critério de aceite: < 5 minutos.
/// Requer Supabase local rodando com migrations da Phase 9.2 aplicadas.
/// Se o Supabase não estiver rodando, o teste é marcado como SKIP (não FAIL).
///
/// Comando:
///   flutter test test/integration/e2e/superadmin/super_admin_onboarding_e2e_test.dart
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/plan_type.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_super_admin_repository.dart';

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/shared/utils/cnpj_validator.dart';

import '../../../infrastructure/postgres/postgres_test_config.dart';
import '../helpers/superadmin_test_config.dart';

const _uuid = Uuid();

int _cnpjCounter = 0;

/// Generates a structurally valid CNPJ using the modulo-11 algorithm.
///
/// Uses timestamp-derived digits for the first 12 positions (base), then
/// computes the two check digits deterministically so the result passes
/// [CnpjValidator.isValid].
String _uniqueCnpj() {
  _cnpjCounter++;
  final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
  final paddedCounter = _cnpjCounter.toString().padLeft(4, '0');
  final combined = '$ts$paddedCounter'.padLeft(14, '0');
  // Take last 12 digits as the base (positions 0–11); compute check digits.
  final base = combined.substring(combined.length - 12);
  final nums = base.split('').map(int.parse).toList();

  const w1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  final sum1 = List.generate(
    12,
    (i) => nums[i] * w1[i],
  ).fold(0, (a, b) => a + b);
  final rem1 = sum1 % 11;
  final d1 = rem1 < 2 ? 0 : 11 - rem1;

  final nums13 = [...nums, d1];
  const w2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  final sum2 = List.generate(
    13,
    (i) => nums13[i] * w2[i],
  ).fold(0, (a, b) => a + b);
  final rem2 = sum2 % 11;
  final d2 = rem2 < 2 ? 0 : 11 - rem2;

  return '$base$d1$d2';
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'SuperAdmin Onboarding E2E',
    skip: !isRunning
        ? 'Supabase local não está rodando. Execute: supabase start'
        : null,
    () {
      late SupabaseClient serviceRoleClient;
      late SupabaseSuperAdminRepository repo;
      late CreateOrganizationHandler handler;

      setUpAll(() async {
        await PostgresTestConfig.createClient();

        // D3: client separado com service_role
        serviceRoleClient = SupabaseClient(
          PostgresTestConfig.supabaseUrl,
          PostgresTestConfig.serviceRoleKey,
        );
        repo = SupabaseSuperAdminRepository(
          serviceRoleClient,
          hmacRequestKey: SuperAdminTestConfig.hmacSecretKeyV1,
        );
        handler = CreateOrganizationHandler(
          repo,
          serviceRoleClient,
          BrazilDateTimeProvider(),
        );
      });

      tearDownAll(() async {
        try {
          await Supabase.instance.dispose();
        } catch (_) {}
        await serviceRoleClient.dispose();
      });

      test(
        'cria org + billing event + convida admin em < 5 minutos (critério de aceite)',
        () async {
          final stopwatch = Stopwatch()..start();

          final cnpj = _uniqueCnpj();
          final adminEmail = 'e2e-${_uuid.v4()}@test.com';
          final superAdminUserId = _uuid.v4();

          final cmd = CreateOrganizationCommand(
            legalName: 'E2E Test Transportes Ltda.',
            tradeName: 'E2E Corp',
            cnpj: cnpj,
            timezone: 'America/Sao_Paulo',
            currencyCode: 'BRL',
            planType: PlanType.professional,
            maxVehicles: 100,
            maxActiveContracts: 20,
            adminEmails: [adminEmail],
            superAdminUserId: superAdminUserId,
            toolCostCents: 50000,
            reason: 'Onboarding E2E test',
          );

          // Fluxo completo: RBAC → validação → createOrg → billingEvent → convite
          final result = await handler.handle(cmd);

          stopwatch.stop();

          // 1. Critério gate: < 5 minutos
          expect(
            stopwatch.elapsed,
            lessThan(const Duration(minutes: 5)),
            reason:
                'Onboarding deve completar em < 5 min. '
                'Levou: ${stopwatch.elapsed.inSeconds}s',
          );

          // 2. Org foi criada
          expect(result.orgId, isNotEmpty);
          final org = await serviceRoleClient
              .from('organizations')
              .select()
              .eq('id', result.orgId)
              .single();
          expect(org['name'], equals('E2E Corp'));
          expect(org['plan_type'], equals('professional'));

          // 3. Billing event registrado (INV-1: append-only)
          final events = await serviceRoleClient
              .from('tenant_billing_events')
              .select()
              .eq('organization_id', result.orgId)
              .eq('event_type', 'ORG_CREATED');
          expect(
            events,
            isNotEmpty,
            reason: 'Deve ter billing event ORG_CREATED',
          );

          // 4. Convite criado para o admin
          final invitations = await serviceRoleClient
              .from('invitations')
              .select()
              .eq('organization_id', result.orgId)
              .eq('email', adminEmail);
          expect(
            invitations,
            isNotEmpty,
            reason: 'Deve ter convite para o admin',
          );
          expect((invitations.first as Map)['role'], equals('TENANT_ADMIN'));

          // 5. Token do convite corresponde ao resultado do handler
          expect(
            (invitations.first as Map)['token'],
            equals(result.invitationTokens.first),
            reason: 'Token do handler deve coincidir com o token no banco',
          );

          // 6. Audit log — Diff format {before: {}, after: {...}} + reason
          final auditLogs = await serviceRoleClient
              .from('system_audit_log')
              .select()
              .eq('organization_id', result.orgId)
              .eq('event_type', 'ORGANIZATION_CREATE');

          expect(
            auditLogs,
            isNotEmpty,
            reason: 'Deve ter audit log ORGANIZATION_CREATE',
          );

          final log = auditLogs.first;
          final payload = log['payload'] as Map;
          final after = payload['after'] as Map;

          expect(
            payload['before'],
            equals({}),
            reason: 'Diff: before deve ser vazio para org nova',
          );
          expect(
            after['trade_name'],
            equals('E2E Corp'),
            reason: 'Diff: after deve conter trade_name',
          );
          expect(
            after['plan_type'],
            equals('professional'),
            reason: 'Diff: after deve conter plan_type',
          );
          expect(
            log['reason'],
            equals('Onboarding E2E test'),
            reason: 'Coluna reason deve ser preenchida',
          );

          debugPrint(
            '[E2E] Onboarding concluído em ${stopwatch.elapsed.inSeconds}s '
            '— orgId: ${result.orgId}',
          );
        },
        timeout: const Timeout(Duration(minutes: 6)),
      );
    },
  );
}
