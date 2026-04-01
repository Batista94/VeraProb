import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/sla_audit/shadow_verdict.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_shadow_verdict_repository.dart';

import 'postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'Phase 10.3 — PostgresShadowVerdictRepository integration tests',
    () {
      late SupabaseClient client;
      late PostgresShadowVerdictRepository repo;
      const uuid = Uuid();

      // ── Shared fixtures ──────────────────────────────────────────────────────

      final verdictTime = DateTime.utc(2026, 6, 15, 10, 0);

      VerdictEvidence makeEvidence() => VerdictEvidence.create(
        clauseRef: 'clause-int-test',
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
      }) => ShadowVerdict.fromEngineResult(
        organizationId: PostgresTestConfig.testOrgId,
        setId: setId,
        contractId: contractId,
        engineVerdict: engineVerdict,
        engineVerdictAtUtc: verdictTime,
        engineVersion: 'veraprob-core_v3',
        verdictEvidence: makeEvidence(),
        createdAtUtc: DateTime.now().toUtc(),
      );

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repo = PostgresShadowVerdictRepository(client);
        }
      });

      // ── 1. save() — round-trip and idempotency ──────────────────────────────

      test(
        '1. save() persists a shadow verdict and can be fetched back',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final verdict = makeVerdict(setId: setId, contractId: contractId);

          await repo.save(verdict);

          final results = await repo.findByOrganization(
            organizationId: PostgresTestConfig.testOrgId,
            fromUtc: DateTime.utc(2026, 1, 1),
            toUtc: DateTime.utc(2027, 1, 1),
          );

          final saved = results.where((v) => v.setId == setId).toList();
          expect(saved, hasLength(1));
          expect(saved.first.contractId, contractId);
          expect(saved.first.engineVerdict, 'noShow');
          expect(
            saved.first.divergenceType,
            ShadowDivergenceType.pendingManual,
          );
          expect(saved.first.traceabilityHash, isNotEmpty);
        },
      );

      test(
        '2. save() is idempotent — second call with same key is a no-op',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final verdict = makeVerdict(setId: setId, contractId: contractId);

          await repo.save(verdict);
          await repo.save(verdict); // must not throw or duplicate

          final results = await repo.findByOrganization(
            organizationId: PostgresTestConfig.testOrgId,
            fromUtc: DateTime.utc(2026, 1, 1),
            toUtc: DateTime.utc(2027, 1, 1),
          );

          final matching = results.where((v) => v.setId == setId).toList();
          expect(
            matching,
            hasLength(1),
            reason: 'Duplicate save must be silently ignored (INV-11)',
          );
        },
      );

      // ── 2. findByOrganization() — filtering and ordering ───────────────────

      test('3. findByOrganization() filters by date range', () async {
        final setId = uuid.v4();
        final contractId = uuid.v4();
        await repo.save(makeVerdict(setId: setId, contractId: contractId));

        // Window that excludes the verdict's created_at (far future)
        final results = await repo.findByOrganization(
          organizationId: PostgresTestConfig.testOrgId,
          fromUtc: DateTime.utc(2030, 1, 1),
          toUtc: DateTime.utc(2031, 1, 1),
        );

        expect(
          results.where((v) => v.setId == setId),
          isEmpty,
          reason: 'Verdict created_at is outside window — must not appear',
        );
      });

      test('4. findByOrganization() enforces tenant isolation', () async {
        final setId = uuid.v4();
        final contractId = uuid.v4();
        await repo.save(makeVerdict(setId: setId, contractId: contractId));

        const otherOrg = '00000000-0000-0000-0000-000000000099';
        await PostgresTestConfig.ensureSentinelOrg(
          client: client,
          id: otherOrg,
        );

        final results = await repo.findByOrganization(
          organizationId: otherOrg, // other org
          fromUtc: DateTime.utc(2026, 1, 1),
          toUtc: DateTime.utc(2027, 1, 1),
        );

        expect(
          results.where((v) => v.setId == setId),
          isEmpty,
          reason: 'Verdict belongs to testOrgId — other org must not see it',
        );
      });

      // ── 3. findDivergent() ──────────────────────────────────────────────────

      test(
        '5. findDivergent() returns only false_positive and false_negative',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final base = makeVerdict(setId: setId, contractId: contractId);

          // Promote to false_positive by applying withManualVerdict
          final classified = base.withManualVerdict(
            manualVerdict: 'rejected',
            manualVerdictAtUtc: DateTime.now().toUtc(),
            manualReviewedBy: '00000000-0000-0000-0000-000000000002',
          );

          // Save the base first (idempotency key = setId::contractId)
          // then update manually via raw client to simulate syncManualVerdicts
          await repo.save(base);
          await client
              .from('shadow_verdicts')
              .update({
                'manual_verdict': classified.manualVerdict,
                'manual_verdict_at_utc': classified.manualVerdictAtUtc!
                    .toIso8601String(),
                'manual_reviewed_by': classified.manualReviewedBy,
                'divergence_type': 'false_positive',
              })
              .eq('organization_id', PostgresTestConfig.testOrgId)
              .eq('set_id', setId)
              .eq('contract_id', contractId);

          final divergent = await repo.findDivergent(
            organizationId: PostgresTestConfig.testOrgId,
            fromUtc: DateTime.utc(2026, 1, 1),
            toUtc: DateTime.utc(2027, 1, 1),
          );

          final match = divergent.where((v) => v.setId == setId).toList();
          expect(match, hasLength(1));
          expect(
            match.first.divergenceType,
            ShadowDivergenceType.falsePositive,
          );
        },
      );

      // ── 4. syncManualVerdicts() ─────────────────────────────────────────────

      test(
        '6. syncManualVerdicts() applies sanction_review_queue decisions',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final reviewerId = uuid.v4();

          // Insert shadow verdict (pending)
          await repo.save(makeVerdict(setId: setId, contractId: contractId));

          // ledger_entry_id has no FK constraint (comment-only). Use a
          // fresh UUID to satisfy NOT NULL + UNIQUE without touching ledger_v2.
          final ledgerEntryId = uuid.v4();

          await client.from('sanction_review_queue').insert({
            'organization_id': PostgresTestConfig.testOrgId,
            'ledger_entry_id': ledgerEntryId,
            'set_id': setId,
            'contract_id': contractId,
            'verdict_evidence': makeEvidence().toJson(),
            'status': 'applied',
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
            'reviewed_by': reviewerId,
          });

          final updated = await repo.syncManualVerdicts(
            organizationId: PostgresTestConfig.testOrgId,
          );

          expect(updated, greaterThanOrEqualTo(1));

          // Fetch and verify the verdict was classified
          final results = await repo.findByOrganization(
            organizationId: PostgresTestConfig.testOrgId,
            fromUtc: DateTime.utc(2026, 1, 1),
            toUtc: DateTime.utc(2027, 1, 1),
          );

          final synced = results.where((v) => v.setId == setId).toList();
          expect(synced, hasLength(1));
          expect(synced.first.manualVerdict, 'applied');
          // noShow + applied → match
          expect(synced.first.divergenceType, ShadowDivergenceType.match);
        },
      );

      test(
        '7. syncManualVerdicts() returns 0 when no pending verdicts exist',
        () async {
          // All existing shadow verdicts should already be synced by prior tests.
          // Insert a fresh one and immediately mark it via direct SQL to simulate
          // it already being classified.
          final setId = uuid.v4();
          final contractId = uuid.v4();
          await repo.save(makeVerdict(setId: setId, contractId: contractId));
          await client
              .from('shadow_verdicts')
              .update({
                'manual_verdict': 'rejected',
                'manual_verdict_at_utc': DateTime.now()
                    .toUtc()
                    .toIso8601String(),
                'manual_reviewed_by': uuid.v4(),
                'divergence_type': 'false_positive',
              })
              .eq('organization_id', PostgresTestConfig.testOrgId)
              .eq('set_id', setId)
              .eq('contract_id', contractId);

          const otherOrg = '00000000-0000-0000-0000-000000000099';
          await PostgresTestConfig.ensureSentinelOrg(
            client: client,
            id: otherOrg,
          );

          // Create an isolated repo pointing at an org with no pending verdicts
          final isolatedRepo = PostgresShadowVerdictRepository(client);
          final count = await isolatedRepo.syncManualVerdicts(
            organizationId: otherOrg,
          );

          expect(count, 0);
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
