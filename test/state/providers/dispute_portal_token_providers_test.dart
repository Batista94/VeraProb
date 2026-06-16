import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/dispute_portal_token_providers.dart';

class _PassthroughTenantValidator extends TenantValidationService {
  _PassthroughTenantValidator() : super(authRepository: _NoopAuthRepo());

  @override
  Future<void> assertTenantMatches({
    required String payloadOrgId,
    required String sessionId,
  }) async {}
}

class _NoopAuthRepo implements IAuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('generate exposes the minted token in state (BUG-02)', () async {
    final queue = InMemorySanctionReviewQueueRepository();
    final ledger = InMemorySlaAuditLedgerRepository();
    await queue.enqueue(
      SanctionReviewQueueEntry(
        id: 'entry-1',
        organizationId: 'org-1',
        ledgerEntryId: 'ledger-1',
        setId: 'set-1',
        contractId: 'contract-1',
        verdictEvidence: VerdictEvidence.create(
          clauseRef: 'no-show-rule-1',
          ruleId: 'rule-001',
          ruleVersion: 1,
          primaryEvidenceLat: -23.5,
          primaryEvidenceLng: -46.6,
          primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 6, 10, 0),
          deltaValue: 15.0,
          thresholdValue: 0.0,
          fineCents: const Money(150000),
          confidenceScore: 100,
        ),
        status: SanctionReviewStatus.disputed,
        createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        tenantValidationServiceProvider.overrideWithValue(
          _PassthroughTenantValidator(),
        ),
        sanctionReviewQueueRepositoryProvider.overrideWithValue(queue),
        slaAuditLedgerRepositoryProvider.overrideWithValue(ledger),
        sanctionReviewCommandRepositoryProvider.overrideWithValue(
          InMemorySanctionReviewCommandRepository(
            queueRepo: queue,
            ledger: ledger,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(
      disputePortalTokenProvider('entry-1').notifier,
    );
    expect(
      container.read(disputePortalTokenProvider('entry-1')),
      const AsyncData<String?>(null),
    );

    final token = await notifier.generate(
      createdByUserId: 'auditor-1',
      actorEmail: 'auditor@veraprob.com',
      callerRole: UserRole.auditor,
      organizationId: 'org-1',
      sessionId: 'session-1',
    );

    expect(token, isNotEmpty);
    final state = container.read(disputePortalTokenProvider('entry-1'));
    expect(state.value, token);
  });
}
