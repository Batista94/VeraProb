import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/vehicle_category.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  final nowUtc = DateTime.parse('2026-04-08T12:00:00Z').toUtc();
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  late InMemoryContractualExecutionStateRepository repo;
  late InMemoryPlanDeclarationRepository planRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ContractualEvaluationEngine engine;

  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;

  setUp(() {
    repo = InMemoryContractualExecutionStateRepository();
    planRepo = InMemoryPlanDeclarationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    final traceRepo = InMemoryEvaluationTraceRepository();
    engine = ContractualEvaluationEngine(
      executionRepo: repo,
      planRepo: planRepo,
      ledgerRepo: ledger,
      traceRepo: traceRepo,
    );
  });

  ContractualExecutionState makeExecState({
    String setId = 'set-1',
    String contractId = 'c-1',
    DateTime? windowStart,
    DateTime? windowEnd,
  }) {
    return ContractualExecutionState.create(
      organizationId: 'org-1',
      setId: setId,
      contractId: contractId,
      planVersion: 1,
      startLatitude: geoLat,
      startLongitude: geoLng,
      startRadiusMeters: geoRadius,
      contractualValue: const Money(15000), // R$ 150.00
      noShowPenaltyBps: 15000,
      windowStartUtc: windowStart ?? DateTime.utc(2026, 3, 1, 6, 0),
      windowEndUtc: windowEnd ?? DateTime.utc(2026, 3, 1, 7, 0),
    );
  }

  Future<void> seedPlan(
    String contractId,
    int gracePeriodMinutes, {
    int penaltyAmountCents = 150000,
  }) async {
    final pattern = ShiftPattern.create(
      index: 0,
      daysOfWeek: [DayOfWeek.monday],
      arrivalTimeLocal: '07:00',
      departureTimeLocal: '06:00',
      timezone: 'America/Sao_Paulo',
      originZoneId: 'zone-origin',
      destinationZoneId: 'zone-dest',
      penalties: SLAPenalties.create(
        noShowPenaltyBps: 15000,
        delayToleranceMinutes: 5,
        delayPenaltyPerMinute: const Money(100),
        downgradePenaltyFlat: const Money(5000),
        gracePeriodMinutes: gracePeriodMinutes,
        baseTripValue: const Money(10000),
      ),
      requiredVehicleCategory: VehicleCategory.conventional,
      weekCycle: WeekCycle.everyWeek,
    );

    final rule = RuleSnapshotItem(
      ruleId: 'r-1',
      ruleType: SlaRuleType.noShowPenalty,
      config: {'penalty_amount_cents': penaltyAmountCents},
      ruleVersion: 1,
      evaluationOrder: 1,
    );

    final declaration = PlanDeclaration.createWithShiftPatterns(
      organizationId: 'org-1',
      contractId: contractId,
      planVersion: 1,
      declaredAtUtc: DateTime.utc(2026, 1, 1),
      declaredByUserId: 'user-1',
      originalFileHash: 'hash-test',
      ruleSnapshot: RuleSnapshot([rule]),
      shiftPatterns: [pattern],
      nowUtc: nowUtc,
    );
    await planRepo.save(declaration);
  }

  VehicleOperationalState makeVehicleState({
    double speed = 0.0,
    DateTime? lastRawPingAt,
  }) {
    return VehicleOperationalState(
      rawSpeed: 0.0,
      vehicleId: 'v-1',
      tripId: 'trip-1',
      latitude: geoLat,
      longitude: geoLng,
      smoothedSpeed: speed,
      motionState: MotionState.stopped,
      connectivityState: ConnectivityState.healthy,
      lastRawPingAt: lastRawPingAt ?? DateTime.utc(2026, 3, 1, 6, 30),
      stateChangedAt: DateTime.utc(2026, 3, 1, 6, 30),
      confidence: 1.0,
      source: 'test',
    );
  }

  group('Validações de Invariantes Solicitadas (Engine de Avaliação)', () {
    test(
      '1. Invariante de Tempo (UTC) - Falha se for chamado com DateTime local no processamento e emissão de Verdict',
      () async {
        final pattern = ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.monday],
          arrivalTimeLocal: '07:00',
          departureTimeLocal: '06:00',
          timezone: 'America/Sao_Paulo',
          originZoneId: 'zone-origin',
          destinationZoneId: 'zone-dest',
          penalties: SLAPenalties.create(
            noShowPenaltyBps: 15000,
            delayToleranceMinutes: 5,
            delayPenaltyPerMinute: const Money(100),
            downgradePenaltyFlat: const Money(5000),
            gracePeriodMinutes: 0,
            baseTripValue: const Money(10000),
          ),
          requiredVehicleCategory: VehicleCategory.conventional,
          weekCycle: WeekCycle.everyWeek,
        );

        const rule = RuleSnapshotItem(
          ruleId: 'r-speed',
          ruleType: SlaRuleType.excessiveSpeed,
          config: {'max_speed_kmh': 60, 'fine_cents': 200000},
          ruleVersion: 1,
          evaluationOrder: 1,
        );

        final declaration = PlanDeclaration.createWithShiftPatterns(
          organizationId: 'org-1',
          contractId: 'c-utc-speed',
          planVersion: 1,
          declaredAtUtc: DateTime.utc(2026, 1, 1),
          declaredByUserId: 'u',
          originalFileHash: 'h',
          ruleSnapshot: const RuleSnapshot([rule]),
          shiftPatterns: [pattern],
          nowUtc: nowUtc,
        );
        await planRepo.save(declaration);

        // Usando uma data NOT-UTC
        final localDate = DateTime(2026, 3, 1, 7, 0);

        final state = makeExecState(
          contractId: 'c-utc-speed',
          windowStart: localDate.toUtc().subtract(const Duration(minutes: 30)),
          windowEnd: localDate.toUtc().add(const Duration(minutes: 30)),
        );
        await repo.save(state);

        final vehicle = makeVehicleState(
          speed: 100.0,
        ); // > 60 pra forçar sanção

        // Expect throw ao processar pq o Timestamp da evidência é o receive/now, e será não-UTC
        expect(
          () async => await engine.processVehicleState(
            vehicle,
            nowUtc: localDate,
            organizationId: 'org-1',
          ),
          throwsA(isA<DomainException>()),
          reason:
              'O sistema deve rejeitar avaliações não-UTC para garantir determinismo forense',
        );
      },
    );

    test(
      '2. Comportamento no exato segundo em que uma janela de carência expira',
      () async {
        final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
        const gracePeriodMinutes = 5;
        await seedPlan('c-grace-exact', gracePeriodMinutes);
        final state = makeExecState(
          contractId: 'c-grace-exact',
          windowStart: windowStart,
        );
        await repo.save(state);

        // O exato segundo em que expira a tolerância (06:05:00 UTC)
        final exactSecond = windowStart.add(
          const Duration(minutes: gracePeriodMinutes),
        );

        await engine.processVehicleState(
          makeVehicleState(lastRawPingAt: exactSecond), // entry ping
          nowUtc: exactSecond,
          organizationId: 'org-1',
        );

        final nextSecond = exactSecond.add(
          const Duration(seconds: 31),
        ); // satisfaz requiredDwell=30s
        await engine.processVehicleState(
          makeVehicleState(lastRawPingAt: nextSecond),
          nowUtc: nextSecond,
          organizationId: 'org-1',
        );

        final r = await repo.findBySetId(state.setId);
        expect(
          r!.status,
          ExecutionStatus.executed,
          reason:
              'No exato segundo que a janela expira (>= start + grace), a avaliação DEVE ser processada e ligada',
        );
      },
    );

    test(
      '3. Processamento de telemetria fora de ordem (Late Arrival) acima de 48h não altera veredito',
      () async {
        await seedPlan('c-late', 0);
        final windowEnd = DateTime.utc(2026, 3, 1, 7, 0); // Termina às 07:00
        final state = makeExecState(contractId: 'c-late', windowEnd: windowEnd);
        await repo.save(state);

        // Passo 1: Executamos o sweep simulando 07:05 (marca como noShow)
        await engine.sweepExpiredObligations(
          nowUtc: DateTime.utc(2026, 3, 1, 7, 5),
          organizationId: 'org-1',
        );

        var r = await repo.findBySetId(state.setId);
        expect(r!.status, ExecutionStatus.noShow);

        // Passo 2: Telemetria dentro da janela do passado chega com 49 horas de atraso na recepção
        final pingReal = DateTime.utc(2026, 3, 1, 6, 30); // Estava lá na hora!
        final receptionLate = windowEnd.add(
          const Duration(hours: 49),
        ); // Chegou atrasado >48h limite

        await engine.processVehicleState(
          makeVehicleState(lastRawPingAt: pingReal),
          nowUtc: pingReal, // event time
          receivedAtUtc: receptionLate, // arrival time
          organizationId: 'org-1',
        );

        // Status tem que permanecer NO SHOW (Determinismo de Janela Fechada)
        r = await repo.findBySetId(state.setId);
        expect(
          r!.status,
          ExecutionStatus.noShow,
          reason:
              'Telemetria que chega após o LateArrivalWindowPolicy (48h) não pode alterar o estado já julgado como noShow.',
        );
      },
    );

    test(
      '4. Severidade nunca ultrapassa 100 BPS do valor do contrato em Penalidades',
      () async {
        // 100 BPS = 1% do valor do contrato.
        // Se Contractual Value = 15000 cents (R$ 150,00). 100 BPS = 150 cents.
        // E configuramos na regra absurdas 500000 cents.
        final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
        final windowEnd = DateTime.utc(2026, 3, 1, 7, 0);
        await seedPlan(
          'c-severity',
          0,
          penaltyAmountCents: 500000,
        ); // Supera os 100 BPS

        final state = makeExecState(
          contractId: 'c-severity',
          windowStart: windowStart,
          windowEnd: windowEnd,
        );
        await repo.save(state);

        await engine.sweepExpiredObligations(
          nowUtc: DateTime.utc(2026, 3, 1, 7, 5),
          organizationId: 'org-1',
        );

        final recommended = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(recommended, isNotEmpty);

        final evidence = recommended.first.payload['verdict_evidence'];
        final fineCents = evidence['fine_cents'] as int;

        // 100 BPS = 1% do valor base.
        const maxBpsAllowed = 100;
        final contractualCents = state.contractualValue.cents;
        final maxSeveridadeCents = (contractualCents * maxBpsAllowed) ~/ 10000;

        expect(
          fineCents,
          lessThanOrEqualTo(maxSeveridadeCents),
          reason:
              'A severidade da multa NUNCA deve ultrapassar 100 BPS (1%) de acordo com a invariante de negócio',
        );
      },
    );
  });
}
