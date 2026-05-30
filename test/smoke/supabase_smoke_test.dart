// veraprob — Smoke Tests: Pipeline B2B + JSONB + Telemetria (Smokes 1–3)
//
// Requer Supabase (local ou cloud). Pulados automaticamente sem credenciais.
//
// ⚠️  IMPORTANTE: As RLS policies exigem app_metadata.org_id no JWT.
//     Um SupabaseClient com a chave `anon` sem sessão autenticada NÃO passa no RLS.
//     Para os testes DB (Smokes 1, 2.4, 2.5, 3), use a SERVICE_ROLE key:
//       Supabase Dashboard → Settings → API → service_role (secret)
//
// ── Como rodar ────────────────────────────────────────────────────────────────
//
//  Cloud (staging) — tudo em uma linha no PowerShell:
//    flutter test test/smoke/supabase_smoke_test.dart --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_KEY=eyJ...(service_role)
//
//  Local (supabase start, porta 54321):
//    flutter test test/smoke/supabase_smoke_test.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_KEY=<service-role-local>
//
// Smoke 4 (Regressão de Navegação, sem Supabase) está em:
//   test/smoke/navigation_smoke_test.dart  →  flutter test test/smoke/navigation_smoke_test.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';

// Domain
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/vehicle_category.dart';

// Application
import 'package:veraprob/application/sla_audit/clone_contract_command.dart';
import 'package:veraprob/application/sla_audit/clone_contract_handler.dart';
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/sla_audit/create_contract_command.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/infrastructure/admin/in_memory_active_vehicle_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_idempotency_store.dart';

// Infrastructure
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_template_repository.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

// ─── Stubs ────────────────────────────────────────────────────────────────────

/// Retorna um contrato draft em memória — permite que o handler ative sem
/// precisar de PostgresContractRepository nos grupos de plano.
class _SmokeContractStub implements ContractRepository {

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async =>
      rows.length;
  const _SmokeContractStub({required this.contractId, required this.orgId});

  final String contractId;
  final String orgId;

  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async {
    if (id != contractId) return null;
    return Contract.reconstitute(
      id: id,
      version: 1,
      organizationId: organizationId,
      name: 'Smoke B2B Contract',
      contractorName: 'SPTRANS Smoke Corp',
      validFromUtc: DateTime.utc(2026, 1, 1),
      validUntilUtc: DateTime.utc(2026, 12, 31),
      status: ContractStatus.draft,
      createdAtUtc: DateTime.utc(2026, 1, 1),
      penaltyMultiplierBps: 10000,
    );
  }

  @override
  Future<Contract> save(Contract contract) async => contract;

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async => [];
}

class _StubZoneRepository implements OperationalZoneRepository {

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async =>
      rows.length;
  @override
  Future<List<OperationalZone>> findByOrganization(
    String organizationId,
  ) async => [
    OperationalZone.create(
      organizationId: organizationId,
      name: 'Stub',
      type: ZoneType.garagem,
    ),
  ];

  @override
  Future<OperationalZone?> findById(
    String id, {
    required String organizationId,
  }) async => null;

  @override
  Future<void> save(OperationalZone zone) async {}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Canonical ShiftPattern do smoke com todos os 7 campos SLA e
/// VehicleCategory.executive (cobre Cenários 3.4, 3.5).
ShiftPattern _buildSmokePattern() {
  final penalties = SLAPenalties.create(
    noShowPenaltyBps: 20000,
    delayToleranceMinutes: 10,
    delayPenaltyPerMinute: const Money(150), // R$ 1,50/min
    downgradePenaltyFlat: const Money(25000), // R$ 250,00
    noShowThresholdMinutes: 45, // não-default → valida persistência
    earlyArrivalToleranceMinutes: 3, // não-default
    dwellTimeMinutes: 5, // não-default
  );

  return ShiftPattern.create(
    index: 0,
    daysOfWeek: [
      DayOfWeek.monday,
      DayOfWeek.tuesday,
      DayOfWeek.wednesday,
      DayOfWeek.thursday,
      DayOfWeek.friday,
    ],
    arrivalTimeLocal: '08:00',
    departureTimeLocal: '18:00',
    timezone: 'America/Sao_Paulo',
    originZoneId: 'zone-origin-smoke',
    destinationZoneId: 'zone-dest-smoke',
    penalties: penalties,
    requiredVehicleCategory: VehicleCategory.executive,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// main
// ─────────────────────────────────────────────────────────────────────────────

class _SmokeMockAuth extends Mock implements IAuthRepository {}

void main() {
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: '');
  final hasCredentials = supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  // ── Infra compartilhada pelos grupos 1–3 ─────────────────────────────────
  late SupabaseClient client;
  late PostgresContractRepository contractRepo;
  late PostgresPlanDeclarationRepository planRepo;
  late PostgresSlaAuditLedgerRepository ledgerRepo;
  late PostgresContractualExecutionStateRepository executionRepo;
  late CreateContractHandler createHandler;
  late DeclareContractualPlanHandler declareHandler;
  late ContractualEvaluationEngine engine;

  // IDs únicos por run — evita colisão no banco entre runs repetidos
  final runId = const Uuid().v4().substring(0, 8);
  final contractId = const Uuid().v4(); // UUID válido para FK constraint
  // org-1 UUID fixo — deve existir na tabela organizations do ambiente de teste
  // Se o ambiente não tiver este UUID, insira via Supabase Dashboard ou SQL:
  //   INSERT INTO organizations (id, name) VALUES ('00000000-0000-0000-0000-000000000001', 'Smoke Org') ON CONFLICT DO NOTHING;
  const orgId = '00000000-0000-0000-0000-000000000001';
  const planVersion = 1;
  final baseTimeUtc = DateTime.utc(2026, 3, 12, 8, 0);

  // Estado compartilhado entre grupos 1 → 2 → 3
  String? declaredPlanId;
  String? smokeSetId;

  // Initialize IANA timezone database unconditionally so that pure-domain
  // tests (Smoke 2.1–2.3) that call ShiftPattern.create() can run even
  // without Supabase credentials.  BrazilTime.ensureInitialized() is
  // idempotent, so the second call inside the credentials block is a no-op.
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  if (hasCredentials) {
    setUpAll(() async {
      client = SupabaseClient(supabaseUrl, supabaseKey);

      contractRepo = PostgresContractRepository(client);
      planRepo = PostgresPlanDeclarationRepository(client);
      ledgerRepo = PostgresSlaAuditLedgerRepository(client);
      executionRepo = PostgresContractualExecutionStateRepository(
        client,
        UtcDateTimeProvider(),
      );

      final clock = FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0));

      final mockAuth = _SmokeMockAuth();
      when(() => mockAuth.getUserBySessionId(any<String>())).thenAnswer(
        (_) async => const domain.AuthUser(id: 'user-1', tenantId: orgId),
      );
      final tenantValidator = TenantValidationService(authRepository: mockAuth);

      createHandler = CreateContractHandler(
        tenantValidator: tenantValidator,
        contractRepository: contractRepo,
        ledger: ledgerRepo,
        clock: clock,
      );

      declareHandler = DeclareContractualPlanHandler(
        tenantValidator: tenantValidator,
        repository: planRepo,
        ledger: ledgerRepo,
        // Stub em memória — ativa o contrato no domínio sem exigir upsert
        contractRepository: _SmokeContractStub(
          contractId: contractId,
          orgId: orgId,
        ),
        zoneRepository: _StubZoneRepository(),
        vehicleRepository: const InMemoryActiveVehicleRepository(
          countsByOrg: {orgId: 1},
        ),
        clock: clock,
        idempotencyStore: InMemoryIdempotencyStore(),
      );

      engine = ContractualEvaluationEngine(
        executionRepo: executionRepo,
        planRepo: planRepo,
        ledgerRepo: ledgerRepo,
        traceRepo: InMemoryEvaluationTraceRepository(),
        clock: clock,
      );
    });

    tearDownAll(() async {
      await client.dispose();
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SMOKE 1 — Fluxo B2B Completo (Cenários 3.1–3.7, 14.12)
  // ──────────────────────────────────────────────────────────────────────────
  group(
    'Smoke 1: Fluxo B2B Completo (3.1–3.7, 14.12)',
    skip: hasCredentials
        ? false
        : 'Credenciais Supabase ausentes — passe --dart-define=SUPABASE_URL=... SUPABASE_KEY=...',
    () {
      test('1.1 — Contrato criado com status draft', () async {
        final contract = await createHandler.handle(
          CreateContractCommand(
            organizationId: orgId,
            name: 'Smoke B2B $runId',
            contractorName: 'SPTRANS Smoke Corp',
            validFromUtc: DateTime.utc(2026, 1, 1),
            validUntilUtc: DateTime.utc(2026, 12, 31),
            sessionId: 'session-smoke-1',
          ),
        );

        expect(contract.id, isNotEmpty);
        expect(
          contract.status,
          ContractStatus.draft,
          reason: 'Cenário 3.1 — nasce como draft',
        );
        expect(contract.organizationId, orgId);

        // Verificar gravação no Supabase
        final saved = await contractRepo.findById(
          contract.id,
          organizationId: orgId,
        );
        expect(saved, isNotNull, reason: 'Persistido no Supabase');
        expect(saved!.status, ContractStatus.draft);
      });

      test(
        '1.2 — Wizard B2B: plano declarado com VehicleCategory + 7 campos SLA',
        () async {
          final pattern = _buildSmokePattern();
          final hash = sha256
              .convert(utf8.encode('$contractId-v$planVersion-smoke'))
              .toString();

          final cmd = DeclareContractualPlanCommand(
            organizationId: orgId,
            contractId: contractId,
            declaredByUserId: 'smoke-admin',
            planVersion: planVersion,
            originalFileHash: hash,
            declaredAtUtc: DateTime.utc(2026, 4, 8, 0, 0, 0),
            shiftPatterns: [pattern],
            contractualValueCents: 50000, // R$ 500,00
            sessionId: 'session-smoke-b2b',
            idempotencyKey: 'smoke-plan-$runId',
          );

          final plan = await declareHandler.handle(cmd);
          declaredPlanId = plan.id;

          expect(plan.id, isNotEmpty);
          expect(
            plan.isShiftBased,
            isTrue,
            reason: 'Cenário 3.2 — modo B2B (shift-based)',
          );
          expect(plan.shiftPatterns.length, 1);

          final p = plan.shiftPatterns.first;
          expect(
            p.requiredVehicleCategory,
            VehicleCategory.executive,
            reason: 'Cenário 3.5 — categoria do veículo persistida',
          );
          expect(
            p.timezone,
            'America/Sao_Paulo',
            reason: 'Cenário 3.4 — timezone configurado',
          );
          expect(
            p.penalties.noShowThresholdMinutes,
            45,
            reason: 'Campo novo SLA — noShowThresholdMinutes',
          );
          expect(
            p.penalties.earlyArrivalToleranceMinutes,
            3,
            reason: 'Campo novo SLA — earlyArrivalToleranceMinutes',
          );
          expect(
            p.penalties.dwellTimeMinutes,
            5,
            reason: 'Campo novo SLA — dwellTimeMinutes',
          );
        },
      );

      test('1.3 — Plano persistido no Supabase com versão correta', () async {
        expect(
          declaredPlanId,
          isNotNull,
          reason: 'Dependência: Smoke 1.2 deve passar primeiro',
        );

        final plans = await planRepo.findByContract(
          contractId,
          organizationId: orgId,
        );
        expect(plans.length, 1, reason: 'Exatamente 1 plano no banco');
        expect(plans.first.id, declaredPlanId);
        expect(plans.first.planVersion, planVersion);
        expect(
          plans.first.isShiftBased,
          isTrue,
          reason:
              'ShiftPatterns restaurados do banco (via shift_patterns_payload)',
        );
      });
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // SMOKE 2 — Integridade JSONB (Cenários 7.4, 14.4)
  // ──────────────────────────────────────────────────────────────────────────
  group('Smoke 2: Integridade JSONB (7.4, 14.4)', () {
    // 2.1–2.3 são testes de domínio puro — não precisam de Supabase

    test('2.1 — [domínio] SLAPenalties.toJson() contém todos os 7 campos', () {
      final penalties = SLAPenalties.create(
        noShowPenaltyBps: 25000,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: const Money(200),
        downgradePenaltyFlat: const Money(30000),
        noShowThresholdMinutes: 45,
        earlyArrivalToleranceMinutes: 3,
        dwellTimeMinutes: 5,
      );
      final json = penalties.toJson();

      expect(json, contains('noShowPenaltyBps'));
      expect(json, contains('delayToleranceMinutes'));
      expect(json, contains('delayPenaltyPerMinuteCents'));
      expect(json, contains('downgradePenaltyFlatCents'));
      expect(
        json,
        contains('noShowThresholdMinutes'),
        reason: 'Campo novo Sprint 5.10',
      );
      expect(
        json,
        contains('earlyArrivalToleranceMinutes'),
        reason: 'Campo novo Sprint 5.10',
      );
      expect(
        json,
        contains('dwellTimeMinutes'),
        reason: 'Campo novo Sprint 5.10',
      );

      // Valores não-default persistidos corretamente
      expect(json['noShowThresholdMinutes'], 45);
      expect(json['earlyArrivalToleranceMinutes'], 3);
      expect(json['dwellTimeMinutes'], 5);
    });

    test(
      '2.2 — [domínio] ShiftPattern.toJson() contém requiredVehicleCategory',
      () {
        final pattern = _buildSmokePattern();
        final json = pattern.toJson();

        expect(
          json,
          contains('requiredVehicleCategory'),
          reason: 'Campo Sprint 5.10',
        );
        expect(json['requiredVehicleCategory'], 'executive');

        final penaltiesJson = json['penalties'] as Map<String, dynamic>;
        expect(penaltiesJson, contains('noShowThresholdMinutes'));
        expect(penaltiesJson, contains('earlyArrivalToleranceMinutes'));
        expect(penaltiesJson, contains('dwellTimeMinutes'));
      },
    );

    test(
      '2.3 — [domínio] SLAPenalties round-trip (toJson → fromJson) preserva valores',
      () {
        final original = SLAPenalties.create(
          noShowPenaltyBps: 20000,
          delayToleranceMinutes: 10,
          delayPenaltyPerMinute: const Money(150),
          downgradePenaltyFlat: const Money(25000),
          noShowThresholdMinutes: 45,
          earlyArrivalToleranceMinutes: 3,
          dwellTimeMinutes: 5,
        );

        final restored = SLAPenalties.fromJson(original.toJson());

        expect(restored.noShowThresholdMinutes, 45);
        expect(restored.earlyArrivalToleranceMinutes, 3);
        expect(restored.dwellTimeMinutes, 5);
        expect(restored.noShowPenaltyBps, 20000);
        expect(restored.delayToleranceMinutes, 10);
        expect(restored.delayPenaltyPerMinute.cents, 150);
        expect(restored.downgradePenaltyFlat.cents, 25000);
      },
    );

    test(
      '2.4 — [db] shift_patterns_payload persiste estrutura JSONB correta',
      skip: hasCredentials ? false : 'Credenciais Supabase ausentes.',
      () async {
        expect(
          declaredPlanId,
          isNotNull,
          reason: 'Dependência: Smoke 1.2 deve passar primeiro',
        );

        final raw = await client
            .from('plan_declarations')
            .select('shift_patterns_payload, organization_id')
            .eq('id', declaredPlanId!)
            .single();

        // Cenário 14.4 — isolamento de tenant
        expect(
          raw['organization_id'],
          orgId,
          reason: 'organization_id deve corresponder ao tenant correto',
        );

        // Coluna JSONB preenchida
        final payload = raw['shift_patterns_payload'];
        expect(
          payload,
          isNotNull,
          reason: 'shift_patterns_payload deve estar gravado (não null)',
        );
        final patterns = payload as List;
        expect(patterns, isNotEmpty);

        final first = patterns.first as Map<String, dynamic>;
        expect(first, contains('requiredVehicleCategory'));
        expect(first['requiredVehicleCategory'], 'executive');

        final p = first['penalties'] as Map<String, dynamic>;
        expect(p['noShowThresholdMinutes'], 45);
        expect(p['earlyArrivalToleranceMinutes'], 3);
        expect(p['dwellTimeMinutes'], 5);
      },
    );

    test(
      '2.5 — [db] organization_id em contracts corresponde ao tenant (Cenário 7.4)',
      skip: hasCredentials ? false : 'Credenciais Supabase ausentes.',
      () async {
        final rows = await client
            .from('contracts')
            .select('organization_id')
            .like('name', '%Smoke B2B $runId%');

        expect(
          rows,
          isNotEmpty,
          reason: 'Contrato do run deve existir no banco',
        );
        for (final row in rows) {
          expect(
            row['organization_id'],
            orgId,
            reason: 'Nenhum registro deve vazar para outro tenant',
          );
        }
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SMOKE 3 — Simulador de Telemetria (Cenário 6.1)
  // ──────────────────────────────────────────────────────────────────────────
  group(
    'Smoke 3: Simulador de Telemetria (Cenário 6.1)',
    skip: hasCredentials ? false : 'Credenciais Supabase ausentes.',
    () {
      test('3.1 — SET criado com status planned', () async {
        expect(
          declaredPlanId,
          isNotNull,
          reason: 'Dependência: Smoke 1.2 deve passar primeiro',
        );

        // O set_id é um identificador de contractual_service_executions.
        // Precisamos inserir essa linha primeiro (causal linkage exigida pelo repo).
        final setId = const Uuid().v4();
        smokeSetId = setId;

        await client.from('contractual_service_executions').insert({
          'set_id': setId,
          'organization_id': orgId,
          'plan_declaration_id': declaredPlanId!,
          'scheduled_start_time_utc': baseTimeUtc
              .subtract(const Duration(minutes: 15))
              .toIso8601String(),
          'scheduled_end_time_utc': baseTimeUtc
              .add(const Duration(minutes: 15))
              .toIso8601String(),
          'start_latitude': -23.5505,
          'start_longitude': -46.6333,
          'start_radius_meters': 100,
          'end_latitude': -23.5505,
          'end_longitude': -46.6333,
          'end_radius_meters': 100,
          'contractual_value_cents': 50000,
          'no_show_penalty_multiplier': 20000,
        });

        final state = ContractualExecutionState.create(
          organizationId: orgId,
          setId: setId,
          contractId: contractId,
          planVersion: planVersion,
          startLatitude: -23.5505,
          startLongitude: -46.6333,
          startRadiusMeters: 100,
          contractualValue: const Money(50000),
          noShowPenaltyBps: 20000,
          windowStartUtc: baseTimeUtc.subtract(const Duration(minutes: 15)),
          windowEndUtc: baseTimeUtc.add(const Duration(minutes: 15)),
        );

        await executionRepo.save(state);

        final saved = await executionRepo.findBySetId(setId);
        expect(saved, isNotNull);
        expect(
          saved!.status.name,
          'planned',
          reason: 'Estado inicial deve ser planned',
        );
      });

      test(
        '3.2 — GPS na geofence → status = completed após dwell time satisfeito',
        () async {
          expect(
            smokeSetId,
            isNotNull,
            reason: 'Dependência: Smoke 3.1 deve passar primeiro',
          );

          final vehicle = VehicleOperationalState(
            rawSpeed: 0.0,
            vehicleId: 'smoke-vehicle-001',
            tripId: 'smoke-trip-$runId',
            latitude: -23.5505, // centro exato da geofence
            longitude: -46.6333,
            smoothedSpeed: 0,
            motionState: MotionState.stopped,
            connectivityState: ConnectivityState.healthy,
            lastRawPingAt: baseTimeUtc,
            stateChangedAt: baseTimeUtc,
            confidence: 1.0,
            source: 'gps',
          );

          // Tick 1: dentro da geofence — inicia dwell timer
          await engine.processVehicleState(
            vehicle,
            nowUtc: baseTimeUtc,
            organizationId: orgId,
          );

          final stateT1 = await executionRepo.findBySetId(smokeSetId!);
          expect(stateT1, isNotNull, reason: 'stateT1 should be initialized');
          expect(
            stateT1!.status.name,
            'inTransit',
            reason:
                'Dwell time ainda não satisfeito (transição automática para inTransit)',
          );

          // Tick 2: 31 s depois → dwell satisfeito → bind
          final bindTime = baseTimeUtc.add(const Duration(seconds: 31));
          await engine.processVehicleState(
            vehicle,
            nowUtc: bindTime,
            organizationId: orgId,
          );

          final stateT2 = await executionRepo.findBySetId(smokeSetId!);
          expect(stateT2, isNotNull, reason: 'stateT2 should be initialized');
          expect(
            stateT2!.status.name,
            'completed',
            reason:
                'Cenário 6.1 — telemetria válida muda status para completed',
          );
          expect(stateT2.boundVehicleId, 'smoke-vehicle-001');
          expect(stateT2.bindingTimestampUtc, bindTime);
        },
      );
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // SMOKE 5 — Sprint 5.11: Clone de Contrato + SLA Templates (DB)
  // ──────────────────────────────────────────────────────────────────────────
  group(
    'Smoke 5: Clone de Contrato + SLA Templates (5.11)',
    skip: hasCredentials ? false : 'Credenciais Supabase ausentes.',
    () {
      String? sourceContractId;
      String? cloneContractId;
      String? templateId;
      late PostgresSlaTemplateRepository templateRepo;
      late CloneContractHandler cloneHandler;

      setUpAll(() {
        templateRepo = PostgresSlaTemplateRepository(client);

        final mockAuthClone = _SmokeMockAuth();
        when(() => mockAuthClone.getUserBySessionId(any<String>())).thenAnswer(
          (_) async => const domain.AuthUser(id: 'user-1', tenantId: orgId),
        );
        final cloneTenantValidator = TenantValidationService(
          authRepository: mockAuthClone,
        );

        cloneHandler = CloneContractHandler(
          tenantValidator: cloneTenantValidator,
          contractRepository: contractRepo,
          ledger: ledgerRepo,
          clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
        );
      });

      test('5.1 — Clone cria draft com clonedFromContractId correto', () async {
        // Cria contrato-fonte real no banco
        final source = await createHandler.handle(
          CreateContractCommand(
            organizationId: orgId,
            name: 'Smoke Source $runId',
            contractorName: 'SPTRANS Source Corp',
            validFromUtc: DateTime.utc(2026, 1, 1),
            validUntilUtc: DateTime.utc(2026, 12, 31),
            sessionId: 'session-smoke-5',
          ),
        );
        sourceContractId = source.id;

        final clone = await cloneHandler.handle(
          CloneContractCommand(
            organizationId: orgId,
            sourceContractId: source.id,
            name: 'Smoke Clone $runId',
            contractorName: source.contractorName,
            sessionId: 'session-smoke-clone-1',
          ),
          validFromUtc: DateTime.utc(2026, 7, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        );
        cloneContractId = clone.id;

        expect(clone.id, isNotEmpty);
        expect(
          clone.status,
          ContractStatus.draft,
          reason: 'Clone nasce como draft',
        );
        expect(
          clone.organizationId,
          orgId,
          reason: 'organization_id do JWT, nunca do contrato-fonte',
        );
        expect(
          clone.clonedFromContractId,
          source.id,
          reason: 'Auditoria: campo aponta para o contrato de origem',
        );
      });

      test('5.2 — Clone cross-tenant rejeitado com DomainException', () async {
        await expectLater(
          () => cloneHandler.handle(
            CloneContractCommand(
              organizationId: orgId,
              sourceContractId: const Uuid().v4(), // ID inexistente nesta org
              name: 'Smoke Malicious Clone',
              contractorName: 'Evil Corp',
              sessionId: 'session-smoke-clone-2',
            ),
            validFromUtc: DateTime.utc(2026, 7, 1),
            validUntilUtc: DateTime.utc(2026, 12, 31),
          ),
          throwsA(isA<DomainException>()),
          reason: 'Source não encontrado na org → DomainException',
        );
      });

      test(
        '5.3 — [db] cloned_from_contract_id persistido no Supabase',
        () async {
          expect(
            cloneContractId,
            isNotNull,
            reason: 'Dependência: Smoke 5.1 deve passar primeiro',
          );
          expect(sourceContractId, isNotNull);

          final row = await client
              .from('contracts')
              .select('cloned_from_contract_id, status, organization_id')
              .eq('id', cloneContractId!)
              .single();

          expect(
            row['cloned_from_contract_id'],
            sourceContractId,
            reason: 'Campo de auditoria persistido corretamente',
          );
          expect(row['status'], 'draft');
          expect(row['organization_id'], orgId);
        },
      );

      test('5.4 — SlaTemplate save + findByOrganization round-trip', () async {
        final template = SlaTemplate.create(
          organizationId: orgId,
          name: 'Smoke Template $runId',
          description: 'Template criado pelo smoke 5.11',
          penalties: SLAPenalties.create(
            noShowPenaltyBps: 15000,
            delayToleranceMinutes: 5,
            delayPenaltyPerMinute: const Money(100),
            downgradePenaltyFlat: const Money(20000),
            noShowThresholdMinutes: 30,
            earlyArrivalToleranceMinutes: 2,
            dwellTimeMinutes: 3,
          ),
        );
        templateId = template.id;

        await templateRepo.save(template);

        final list = await templateRepo.findByOrganization(orgId);
        final saved = list.where((t) => t.id == template.id).firstOrNull;

        expect(saved, isNotNull, reason: 'Template persistido e recuperado');
        expect(saved!.name, 'Smoke Template $runId');
        expect(saved.organizationId, orgId);
        expect(saved.description, 'Template criado pelo smoke 5.11');
      });

      test(
        '5.5 — [db] penalties_payload JSONB preserva todos os 7 campos SLA',
        () async {
          expect(
            templateId,
            isNotNull,
            reason: 'Dependência: Smoke 5.4 deve passar primeiro',
          );

          final row = await client
              .from('sla_templates')
              .select('penalties_payload, organization_id')
              .eq('id', templateId!)
              .single();

          expect(
            row['organization_id'],
            orgId,
            reason: 'Isolamento de tenant — organization_id correto',
          );

          final p = row['penalties_payload'] as Map<String, dynamic>;
          expect(
            p['noShowThresholdMinutes'],
            30,
            reason: 'Campo Sprint 5.10 persistido no template',
          );
          expect(p['earlyArrivalToleranceMinutes'], 2);
          expect(p['dwellTimeMinutes'], 3);
          expect(p['noShowPenaltyBps'], 15000);
          expect(p['delayToleranceMinutes'], 5);
          expect(p['delayPenaltyPerMinuteCents'], 100);
          expect(p['downgradePenaltyFlatCents'], 20000);
        },
      );
    },
  );
}
