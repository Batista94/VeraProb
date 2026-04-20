import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/reporting_service.dart';
import 'package:veraprob/application/sla_audit/shadow_mode_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_canonical_fact_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_shadow_mode_repository.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

void main() {
  final periodStart = DateTime.utc(2026, 3, 1);
  final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);
  const orgId = 'org-acme';
  const contractId = 'contract-bus-1';

  late InMemoryShadowModeRepository shadowRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late InMemoryCanonicalFactRepository canonicalFactRepo;
  late ReportingService reportingService;
  late ShadowModeService service;

  ContractualFinancialDailySnapshot makeSnapshot({
    required DateTime date,
    Money totalRevenue = const Money(100000),
    int noShowCount = 2,
    int evidenceGapCount = 1,
  }) => ContractualFinancialDailySnapshot.create(
    organizationId: orgId,
    contractId: contractId,
    operationalDateUtc: date,
    operationalTimezone: 'America/Sao_Paulo',
    closedAtUtc: date.add(const Duration(hours: 1)),
    totalContractedRevenue: totalRevenue,
    protectedRevenue: Money((totalRevenue.cents * 0.80).round()),
    revenueAtRisk: Money((totalRevenue.cents * 0.10).round()),
    lostRevenue: Money((totalRevenue.cents * 0.10).round()),
    totalObligations: 20,
    executedCount: 17,
    noShowCount: noShowCount,
    evidenceGapCount: evidenceGapCount,
    lastLedgerEntryId: '100',
  );

  CanonicalFact makeCanonicalFact({
    required IngestionIntegrityFlag flag,
    required DateTime timestamp,
  }) => CanonicalFact.create(
    organizationId: orgId,
    deviceId: 'device-001',
    assetId: 'asset-bus-1',
    sourceAdapter: 'sascar_v1',
    gpsTimestamp: timestamp,
    receivedAtUtc: timestamp.add(const Duration(seconds: 5)),
    lat: -23.5505,
    lng: -46.6333,
    accuracyMeters: 5.0,
    rawPayloadId: 'raw-001',
    integrityFlag: flag,
  );

  setUp(() {
    shadowRepo = InMemoryShadowModeRepository();
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    canonicalFactRepo = InMemoryCanonicalFactRepository();
    reportingService = ReportingService(snapshotRepo: snapshotRepo);
    service = ShadowModeService(
      simulationRepo: shadowRepo,
      reportingService: reportingService,
      canonicalFactRepo: canonicalFactRepo,
      dateTimeProvider: BrazilDateTimeProvider(),
    );
  });

  group('ShadowModeService.runSimulation — ROI computation', () {
    test('persists simulation to repository', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      await service.runSimulation(
        organizationId: orgId,
        simulationName: 'Março 2026',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        baselineDisputeRateBps: 6000,
        manualEnforcementCostPerIncident: 5000,
        platformSubscriptionCost: 50000,
        generatedByUserId: 'user-admin-1',
      );

      expect(shadowRepo.count, equals(1));
    });

    test('simulatedLostRevenue = actualLost × (1 - disputeRate/100)', () async {
      // lost = 10% of 100000 = 10000 cents per day × 1 day
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      final sim = await service.runSimulation(
        organizationId: orgId,
        simulationName: 'Test',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        baselineDisputeRateBps: 6000, // 60% would have been disputed (lost)
        manualEnforcementCostPerIncident: 0,
        platformSubscriptionCost: 100000,
        generatedByUserId: 'user-admin-1',
      );

      // actualLost = 10000 cents; simulatedLost = 10000 × (1 - 0.60) = 4000
      expect(sim.simulatedLostRevenue.cents, equals(4000));
    });

    test('revenueProtectedByPlatform includes labor cost savings', () async {
      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          noShowCount: 3,
          evidenceGapCount: 0,
        ),
      );

      final sim = await service.runSimulation(
        organizationId: orgId,
        simulationName: 'Test',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        baselineDisputeRateBps: 5000,
        manualEnforcementCostPerIncident: 2000, // R$ 20 per incident
        platformSubscriptionCost: 100000,
        generatedByUserId: 'user-admin-1',
      );

      // incidentCount = noShowCount + evidenceGapCount = 3 + 0 = 3
      // manualCostTotal = 2000 × 3 = 6000
      // actualLost = 10000; simulatedLost = 10000 × 0.5 = 5000
      // protected = (10000 - 5000) + 6000 = 11000
      expect(sim.revenueProtectedByPlatform.cents, equals(11000));
    });

    test('roiPercentage = (protected / subscriptionCost) × 100', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      final sim = await service.runSimulation(
        organizationId: orgId,
        simulationName: 'Test',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        baselineDisputeRateBps: 6000,
        manualEnforcementCostPerIncident: 0,
        platformSubscriptionCost: 6000, // R$ 60
        generatedByUserId: 'user-admin-1',
      );

      // actualLost = 10000; simulatedLost = 4000; protected = 6000
      // roi = 6000 / 6000 * 10000 = 10000 bps
      expect(sim.roiPercentageBps, equals(10000));
    });

    test('same parameters → same ROI (idempotency)', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      final sim1 = await service.runSimulation(
        organizationId: orgId,
        simulationName: 'Test',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        baselineDisputeRateBps: 5500,
        manualEnforcementCostPerIncident: 1000,
        platformSubscriptionCost: 50000,
        generatedByUserId: 'user-admin-1',
      );

      final sim2 = await service.runSimulation(
        organizationId: orgId,
        simulationName: 'Test',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        baselineDisputeRateBps: 5500,
        manualEnforcementCostPerIncident: 1000,
        platformSubscriptionCost: 50000,
        generatedByUserId: 'user-admin-1',
      );

      expect(sim1.roiPercentageBps, equals(sim2.roiPercentageBps));
      expect(sim1.simulatedLostRevenue, equals(sim2.simulatedLostRevenue));
      expect(
        sim1.revenueProtectedByPlatform,
        equals(sim2.revenueProtectedByPlatform),
      );
    });
  });

  group(
    'ShadowModeService.runSimulation — Evidence quality from canonical_facts',
    () {
      test(
        'evidenceQualityRate = 100% when no facts exist (empty period)',
        () async {
          await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

          final sim = await service.runSimulation(
            organizationId: orgId,
            simulationName: 'Test',
            periodStartUtc: periodStart,
            periodEndUtc: periodEnd,
            baselineDisputeRateBps: 5000,
            manualEnforcementCostPerIncident: 0,
            platformSubscriptionCost: 100000,
            generatedByUserId: 'user-admin-1',
          );

          expect(sim.evidenceQualityRateBps, equals(10000));
        },
      );

      test(
        'evidenceQualityRate computed from OK / total canonical_facts',
        () async {
          await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

          final t = DateTime.utc(2026, 3, 10, 8);
          // 8 OK facts + 2 flagged = 80% quality
          for (int i = 0; i < 8; i++) {
            await canonicalFactRepo.save(
              makeCanonicalFact(
                flag: IngestionIntegrityFlag.ok,
                timestamp: t.add(Duration(minutes: i)),
              ),
            );
          }
          await canonicalFactRepo.save(
            makeCanonicalFact(
              flag: IngestionIntegrityFlag.kinematicAnomaly,
              timestamp: t.add(const Duration(minutes: 10)),
            ),
          );
          await canonicalFactRepo.save(
            makeCanonicalFact(
              flag: IngestionIntegrityFlag.lowAccuracy,
              timestamp: t.add(const Duration(minutes: 11)),
            ),
          );

          final sim = await service.runSimulation(
            organizationId: orgId,
            simulationName: 'Test',
            periodStartUtc: periodStart,
            periodEndUtc: periodEnd,
            baselineDisputeRateBps: 5000,
            manualEnforcementCostPerIncident: 0,
            platformSubscriptionCost: 100000,
            generatedByUserId: 'user-admin-1',
          );

          expect(sim.evidenceQualityRateBps, equals(8000));
        },
      );

      test(
        'evidenceQualityAttribution does NOT mention veraprob as cause when quality is low',
        () async {
          await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

          final t = DateTime.utc(2026, 3, 10, 8);
          // 60% quality (6 OK, 4 flagged) — triggers hardware attribution
          for (int i = 0; i < 6; i++) {
            await canonicalFactRepo.save(
              makeCanonicalFact(
                flag: IngestionIntegrityFlag.ok,
                timestamp: t.add(Duration(minutes: i)),
              ),
            );
          }
          for (int i = 6; i < 10; i++) {
            await canonicalFactRepo.save(
              makeCanonicalFact(
                flag: IngestionIntegrityFlag.nullIsland,
                timestamp: t.add(Duration(minutes: i)),
              ),
            );
          }

          final sim = await service.runSimulation(
            organizationId: orgId,
            simulationName: 'Test',
            periodStartUtc: periodStart,
            periodEndUtc: periodEnd,
            baselineDisputeRateBps: 5000,
            manualEnforcementCostPerIncident: 0,
            platformSubscriptionCost: 100000,
            generatedByUserId: 'user-admin-1',
          );

          final attribution = sim.evidenceQualityAttribution;

          // PO directive: must attribute to hardware, not veraprob software
          expect(attribution, contains('hardware'));
          expect(
            attribution,
            contains('veraprob processou 100% dos sinais válidos recebidos'),
          );
          // Must NOT imply veraprob is at fault
          expect(
            attribution.toLowerCase(),
            isNot(contains('falha do sistema')),
          );
          expect(
            attribution.toLowerCase(),
            isNot(contains('erro do veraprob')),
          );
          expect(attribution.toLowerCase(), isNot(contains('bug')));
        },
      );

      test(
        'evidenceQualityAttribution praises good quality when >= 95%',
        () async {
          await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

          final t = DateTime.utc(2026, 3, 10, 8);
          for (int i = 0; i < 20; i++) {
            await canonicalFactRepo.save(
              makeCanonicalFact(
                flag: IngestionIntegrityFlag.ok,
                timestamp: t.add(Duration(minutes: i)),
              ),
            );
          }

          final sim = await service.runSimulation(
            organizationId: orgId,
            simulationName: 'Test',
            periodStartUtc: periodStart,
            periodEndUtc: periodEnd,
            baselineDisputeRateBps: 5000,
            manualEnforcementCostPerIncident: 0,
            platformSubscriptionCost: 100000,
            generatedByUserId: 'user-admin-1',
          );

          expect(sim.evidenceQualityRateBps, equals(10000));
          expect(
            sim.evidenceQualityAttribution.toLowerCase(),
            contains('excelente'),
          );
        },
      );
    },
  );

  group('ShadowModeService.listSimulations', () {
    test(
      'returns simulations for the organization ordered by date DESC',
      () async {
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));
        await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 2, 1)));

        await service.runSimulation(
          organizationId: orgId,
          simulationName: 'Fevereiro 2026',
          periodStartUtc: DateTime.utc(2026, 2, 1),
          periodEndUtc: DateTime.utc(2026, 2, 28),
          baselineDisputeRateBps: 5000,
          manualEnforcementCostPerIncident: 0,
          platformSubscriptionCost: 50000,
          generatedByUserId: 'user-1',
        );

        await service.runSimulation(
          organizationId: orgId,
          simulationName: 'Março 2026',
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          baselineDisputeRateBps: 5000,
          manualEnforcementCostPerIncident: 0,
          platformSubscriptionCost: 50000,
          generatedByUserId: 'user-1',
        );

        final list = await service.listSimulations(organizationId: orgId);
        expect(list, hasLength(2));
      },
    );

    test('does not return simulations from other organizations', () async {
      await snapshotRepo.save(makeSnapshot(date: DateTime.utc(2026, 3, 1)));

      await service.runSimulation(
        organizationId: 'org-other',
        simulationName: 'Other Org Sim',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        baselineDisputeRateBps: 5000,
        manualEnforcementCostPerIncident: 0,
        platformSubscriptionCost: 50000,
        generatedByUserId: 'user-1',
      );

      final list = await service.listSimulations(organizationId: orgId);
      expect(list, isEmpty);
    });
  });
}
