import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/shadow_comparison_service.dart';
import 'package:veraprob/domain/sla_audit/shadow_verdict.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_shadow_verdict_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

import '../infrastructure/postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  final skipReason = isRunning
      ? null
      : 'Local Supabase environment is offline.';

  // ── Fixtures ───────────────────────────────────────────────────────────────

  final windowStart = DateTime.utc(2026, 6, 1);
  final windowEnd = DateTime.utc(2026, 6, 30, 23, 59, 59);
  final verdictTime = DateTime.utc(2026, 6, 15, 10, 0);
  final reviewTime = DateTime.utc(2026, 6, 16, 9, 0);
  late String orgId;
  const reviewer = '11111111-1111-1111-1111-111111111111';

  VerdictEvidence makeEvidence() => VerdictEvidence.create(
    clauseRef: 'clause-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5505,
    primaryEvidenceLng: -46.6333,
    primaryEvidenceTimestampUtc: verdictTime,
    deltaValue: 15.0,
    thresholdValue: 0.0,
    fineCents: const Money(150000),
    confidenceScore: 100,
  );

  ShadowVerdict makeVerdict({
    required String setId,
    required String contractId,
    String engineVerdict = 'noShow',
    String? manualVerdict,
  }) {
    final base = ShadowVerdict.fromEngineResult(
      organizationId: orgId,
      setId: setId,
      contractId: contractId,
      engineVerdict: engineVerdict,
      engineVerdictAtUtc: verdictTime,
      engineVersion: 'veraprob-core_v3',
      verdictEvidence: makeEvidence(),
      createdAtUtc: verdictTime,
    );
    if (manualVerdict == null) return base;
    return base.withManualVerdict(
      manualVerdict: manualVerdict,
      manualVerdictAtUtc: reviewTime,
      manualReviewedBy: reviewer,
    );
  }

  group('ShadowComparisonService Integration Tests', skip: skipReason, () {
    late PostgresShadowVerdictRepository repo;
    late ShadowComparisonService service;
    late SupabaseClient client;

    setUpAll(() async {
      client = await PostgresTestConfig.createClient();
    });

    setUp(() async {
      orgId = const Uuid().v4();
      await PostgresTestConfig.ensureSentinelOrg(client: client, id: orgId);

      repo = PostgresShadowVerdictRepository(client);
      service = ShadowComparisonService(
        shadowRepo: repo,
        dateTimeProvider: BrazilDateTimeProvider(),
      );
    });

    // ── Input validation ───────────────────────────────────────────────────────

    group('generateReport — input validation', () {
      test('throws on non-UTC fromUtc', () async {
        await expectLater(
          () => service.generateReport(
            organizationId: orgId,
            fromUtc: DateTime(2026, 6, 1), // local time
            toUtc: windowEnd,
          ),
          throwsArgumentError,
        );
      });

      test('throws on non-UTC toUtc', () async {
        await expectLater(
          () => service.generateReport(
            organizationId: orgId,
            fromUtc: windowStart,
            toUtc: DateTime(2026, 6, 30), // local time
          ),
          throwsArgumentError,
        );
      });

      test('throws when fromUtc is after toUtc', () async {
        await expectLater(
          () => service.generateReport(
            organizationId: orgId,
            fromUtc: windowEnd,
            toUtc: windowStart,
          ),
          throwsArgumentError,
        );
      });
    });

    // ── Empty window ───────────────────────────────────────────────────────────

    group('generateReport — empty window', () {
      test('returns zeroed report when no verdicts exist', () async {
        final report = await service.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.totalEvaluated, 0);
        expect(report.totalCompared, 0);
        expect(report.matchRate, 0.0);
        expect(report.falsePositiveCount, 0);
        expect(report.falseNegativeCount, 0);
        expect(report.pendingManualCount, 0);
        expect(report.divergentEntries, isEmpty);
        // No compared data → critical divergence must NOT fire
        expect(report.criticalDivergenceDetected, isFalse);
      });
    });

    // ── matchRate calculation ──────────────────────────────────────────────────

    group('generateReport — matchRate calculation', () {
      test('matchRate is 100% when all compared verdicts match', () async {
        await repo.save(
          makeVerdict(
            setId: 'set-1',
            contractId: 'c-1',
            manualVerdict: 'applied', // noShow + applied → match
          ),
        );
        await repo.save(
          makeVerdict(
            setId: 'set-2',
            contractId: 'c-2',
            manualVerdict: 'applied',
          ),
        );

        final report = await service.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.totalCompared, 2);
        expect(report.matchRate, 100.0);
        expect(report.falsePositiveCount, 0);
        expect(report.falseNegativeCount, 0);
        expect(report.criticalDivergenceDetected, isFalse);
      });

      test('matchRate is 0% when all compared verdicts diverge', () async {
        // noShow + rejected → false_positive
        await repo.save(
          makeVerdict(
            setId: 'set-1',
            contractId: 'c-1',
            manualVerdict: 'rejected',
          ),
        );
        await repo.save(
          makeVerdict(
            setId: 'set-2',
            contractId: 'c-2',
            manualVerdict: 'rejected',
          ),
        );

        final report = await service.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.matchRate, 0.0);
        expect(report.falsePositiveCount, 2);
        expect(report.criticalDivergenceDetected, isTrue);
      });

      test(
        'matchRate excludes pendingManual entries from denominator',
        () async {
          // 1 match, 1 false_positive, 2 pending → compared=2 → matchRate=50%
          await repo.save(
            makeVerdict(
              setId: 'set-1',
              contractId: 'c-1',
              manualVerdict: 'applied', // match
            ),
          );
          await repo.save(
            makeVerdict(
              setId: 'set-2',
              contractId: 'c-2',
              manualVerdict: 'rejected', // false_positive
            ),
          );
          await repo.save(
            makeVerdict(setId: 'set-3', contractId: 'c-3'),
          ); // pending
          await repo.save(
            makeVerdict(setId: 'set-4', contractId: 'c-4'),
          ); // pending

          final report = await service.generateReport(
            organizationId: orgId,
            fromUtc: windowStart,
            toUtc: windowEnd,
          );

          expect(report.totalEvaluated, 4);
          expect(report.totalCompared, 2);
          expect(report.pendingManualCount, 2);
          expect(report.matchRate, 50.0);
        },
      );
    });

    // ── False positive / false negative counts ─────────────────────────────────

    group('generateReport — FP / FN classification', () {
      test(
        'correctly counts false positives (engine penalty, human rejected)',
        () async {
          await repo.save(
            makeVerdict(
              setId: 'set-1',
              contractId: 'c-1',
              manualVerdict: 'rejected', // noShow + rejected → FP
            ),
          );

          final report = await service.generateReport(
            organizationId: orgId,
            fromUtc: windowStart,
            toUtc: windowEnd,
          );

          expect(report.falsePositiveCount, 1);
          expect(report.falseNegativeCount, 0);
        },
      );

      test(
        'correctly counts false negatives (evidenceGap, human applied)',
        () async {
          await repo.save(
            makeVerdict(
              setId: 'set-1',
              contractId: 'c-1',
              engineVerdict: 'evidenceGap',
              manualVerdict: 'applied', // evidenceGap + applied → FN
            ),
          );

          final report = await service.generateReport(
            organizationId: orgId,
            fromUtc: windowStart,
            toUtc: windowEnd,
          );

          expect(report.falseNegativeCount, 1);
          expect(report.falsePositiveCount, 0);
        },
      );

      test(
        'inhibited + applied is counted as false negative (not hidden as match)',
        () async {
          await repo.save(
            makeVerdict(
              setId: 'set-1',
              contractId: 'c-1',
              engineVerdict: 'inhibited',
              manualVerdict:
                  'applied', // inhibited + applied → FN (engine too lenient)
            ),
          );

          final report = await service.generateReport(
            organizationId: orgId,
            fromUtc: windowStart,
            toUtc: windowEnd,
          );

          expect(report.falseNegativeCount, 1);
          expect(report.falsePositiveCount, 0);
          expect(report.matchRate, 0.0);
        },
      );

      test('inhibited + rejected is counted as match', () async {
        await repo.save(
          makeVerdict(
            setId: 'set-1',
            contractId: 'c-1',
            engineVerdict: 'inhibited',
            manualVerdict: 'rejected', // inhibited + rejected → match
          ),
        );

        final report = await service.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.matchRate, 100.0);
        expect(report.falseNegativeCount, 0);
      });

      test('divergentEntries contains only FP and FN entries', () async {
        await repo.save(
          makeVerdict(
            setId: 'set-1',
            contractId: 'c-1',
            manualVerdict: 'applied', // match — must not appear
          ),
        );
        await repo.save(
          makeVerdict(
            setId: 'set-2',
            contractId: 'c-2',
            manualVerdict: 'rejected', // false_positive — must appear
          ),
        );
        await repo.save(
          makeVerdict(setId: 'set-3', contractId: 'c-3'),
        ); // pending

        final report = await service.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.divergentEntries.length, 1);
        expect(
          report.divergentEntries.first.divergenceType,
          ShadowDivergenceType.falsePositive,
        );
      });
    });

    // ── Critical divergence threshold ─────────────────────────────────────────

    group('generateReport — critical divergence threshold', () {
      test('does NOT fire when matchRate == threshold exactly', () async {
        // 4 match, 1 FP → matchRate = 80.0% — exactly at threshold, not below
        for (var i = 1; i <= 4; i++) {
          await repo.save(
            makeVerdict(
              setId: 'set-$i',
              contractId: 'c-$i',
              manualVerdict: 'applied', // match
            ),
          );
        }
        await repo.save(
          makeVerdict(
            setId: 'set-5',
            contractId: 'c-5',
            manualVerdict: 'rejected', // FP
          ),
        );

        final report = await service.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.matchRate, 80.0);
        expect(report.criticalDivergenceDetected, isFalse);
      });

      test('fires when matchRate is just below threshold (79.9%)', () async {
        // Use custom threshold of 80.0%. 3 match, 1 FP → 75.0%
        final strictService = ShadowComparisonService(
          shadowRepo: repo,
          criticalDivergenceThreshold: 80.0,
          dateTimeProvider: BrazilDateTimeProvider(),
        );
        for (var i = 1; i <= 3; i++) {
          await repo.save(
            makeVerdict(
              setId: 'set-$i',
              contractId: 'c-$i',
              manualVerdict: 'applied', // match
            ),
          );
        }
        await repo.save(
          makeVerdict(
            setId: 'set-4',
            contractId: 'c-4',
            manualVerdict: 'rejected', // FP → matchRate = 75%
          ),
        );

        final report = await strictService.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.matchRate, 75.0);
        expect(report.criticalDivergenceDetected, isTrue);
      });

      test(
        'does NOT fire when totalCompared is zero (no human decisions yet)',
        () async {
          await repo.save(makeVerdict(setId: 'set-1', contractId: 'c-1'));
          await repo.save(makeVerdict(setId: 'set-2', contractId: 'c-2'));

          final report = await service.generateReport(
            organizationId: orgId,
            fromUtc: windowStart,
            toUtc: windowEnd,
          );

          expect(report.totalCompared, 0);
          expect(report.criticalDivergenceDetected, isFalse);
        },
      );

      test('threshold is configurable below default 80%', () async {
        final lenientService = ShadowComparisonService(
          shadowRepo: repo,
          criticalDivergenceThreshold: 50.0,
          dateTimeProvider: BrazilDateTimeProvider(),
        );
        // 1 match, 1 FP → matchRate = 50% (exactly at 50% threshold)
        await repo.save(
          makeVerdict(
            setId: 'set-1',
            contractId: 'c-1',
            manualVerdict: 'applied',
          ),
        );
        await repo.save(
          makeVerdict(
            setId: 'set-2',
            contractId: 'c-2',
            manualVerdict: 'rejected',
          ),
        );

        final report = await lenientService.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.matchRate, 50.0);
        expect(report.criticalDivergenceDetected, isFalse); // 50 is not < 50
      });
    });

    // ── syncManualVerdicts wiring ──────────────────────────────────────────────

    group('generateReport — sync wiring', () {
      test(
        'applies pending manual decisions before computing metrics',
        () async {
          // Insert a pendingManual verdict
          await repo.save(makeVerdict(setId: 'set-1', contractId: 'c-1'));
          expect(
            (await repo.findByOrganization(
              organizationId: orgId,
              fromUtc: windowStart,
              toUtc: windowEnd,
            )).first.divergenceType,
            ShadowDivergenceType.pendingManual,
          );

          // Register a manual decision that syncManualVerdicts will apply
          await client.from('sanction_review_queue').insert({
            'set_id': 'set-1',
            'contract_id': 'c-1',
            'organization_id': orgId,
            'ledger_entry_id': const Uuid().v4(),
            'verdict_evidence': makeEvidence().toJson(),
            'status': 'applied',
            'reviewed_at': reviewTime.toIso8601String(),
            'reviewed_by': reviewer,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });

          final report = await service.generateReport(
            organizationId: orgId,
            fromUtc: windowStart,
            toUtc: windowEnd,
          );

          // After sync, the verdict should now be compared, not pending
          expect(report.totalCompared, 1);
          expect(report.pendingManualCount, 0);
          expect(report.matchRate, 100.0);
        },
      );
    });

    // ── Tenant isolation ───────────────────────────────────────────────────────

    group('generateReport — tenant isolation', () {
      test('only returns verdicts for the requested organization', () async {
        await repo.save(makeVerdict(setId: 'set-1', contractId: 'c-1'));

        // Force-insert by bypassing idempotency key (different org).
        final otherOrgId = const Uuid().v4();
        await PostgresTestConfig.ensureSentinelOrg(
          client: client,
          id: otherOrgId,
        );
        final otherVerdict = ShadowVerdict.fromEngineResult(
          organizationId: otherOrgId,
          setId: 'set-1',
          contractId: 'c-1',
          engineVerdict: 'noShow',
          engineVerdictAtUtc: verdictTime,
          engineVersion: 'v3',
          verdictEvidence: makeEvidence(),
          createdAtUtc: verdictTime,
        );
        await repo.save(otherVerdict);

        final report = await service.generateReport(
          organizationId: orgId,
          fromUtc: windowStart,
          toUtc: windowEnd,
        );

        expect(report.totalEvaluated, 1);
      });
    });
  });
}
