/// E2E: SuperAdmin cria novo tenant via fluxo completo do handler.
///
/// Mede wall-clock — critério de aceite: < 5 minutos.
/// Requer Supabase local rodando com migrations da Phase 9.2 aplicadas.
/// Se o Supabase não estiver rodando, o teste é marcado como SKIP (não FAIL).
///
/// Comando:
///   flutter test test/e2e/super_admin_onboarding_e2e_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_super_admin_repository.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

const _uuid = Uuid();

String _uniqueCnpj() {
  final ts = DateTime.now().millisecondsSinceEpoch.toString().padLeft(14, '0');
  return ts.substring(ts.length - 14);
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
        repo = SupabaseSuperAdminRepository(serviceRoleClient);
        handler = CreateOrganizationHandler(repo, serviceRoleClient);
      });

      tearDownAll(() async {
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
            planType: 'professional',
            maxVehicles: 100,
            maxActiveContracts: 20,
            initialAdminEmail: adminEmail,
            superAdminUserId: superAdminUserId,
          );

          // Fluxo completo: RBAC → validação → createOrg → billingEvent → convite
          final result = await handler.handle(cmd);

          stopwatch.stop();

          // 1. Critério gate: < 5 minutos
          expect(
            stopwatch.elapsed,
            lessThan(const Duration(minutes: 5)),
            reason: 'Onboarding deve completar em < 5 min. '
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
          expect(events, isNotEmpty, reason: 'Deve ter billing event ORG_CREATED');

          // 4. Convite criado para o admin
          final invitations = await serviceRoleClient
              .from('invitations')
              .select()
              .eq('organization_id', result.orgId)
              .eq('email', adminEmail);
          expect(invitations, isNotEmpty, reason: 'Deve ter convite para o admin');
          expect(
            (invitations.first as Map)['role'],
            equals('TENANT_ADMIN'),
          );

          // 5. Token do convite corresponde ao resultado do handler
          expect(
            (invitations.first as Map)['token'],
            equals(result.invitationToken),
            reason: 'Token do handler deve coincidir com o token no banco',
          );

          // ignore: avoid_print
          print(
            '[E2E] Onboarding concluído em ${stopwatch.elapsed.inSeconds}s '
            '— orgId: ${result.orgId}',
          );
        },
        timeout: const Timeout(Duration(minutes: 6)),
      );
    },
  );
}
