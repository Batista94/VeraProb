import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/confirm_peer_review_command.dart';
import 'package:veraprob/application/sla_audit/confirm_peer_review_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/dual_control_self_approval_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ConfirmPeerReviewHandler handler;
  late _MockAuthRepository mockAuthRepo;

  final evidence = VerdictEvidence.create(
    clauseRef: 'no-show-rule-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5505,
    primaryEvidenceLng: -46.6333,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 8, 12, 10, 0),
    deltaValue: 15.0,
    thresholdValue: 0.0,
    fineCents: const Money(200000),
    confidenceScore: 100,
  );

  SanctionReviewQueueEntry peerReviewEntry() => SanctionReviewQueueEntry(
    id: 'entry-pr',
    organizationId: 'org-1',
    ledgerEntryId: 'ledger-pr',
    setId: 'set-1',
    contractId: 'contract-1',
    verdictEvidence: evidence,
    status: SanctionReviewStatus.pendingPeerReview,
    createdAtUtc: DateTime.utc(2026, 8, 12, 10, 5),
    firstReviewerId: 'auditor-1',
    peerReviewProposedAction: 'APPROVE',
    peerReviewOriginStatus: 'pending',
  );

  ConfirmPeerReviewCommand cmd({
    required String user,
    required UserRole role,
  }) => ConfirmPeerReviewCommand(
    queueEntryId: 'entry-pr',
    confirmedByUserId: user,
    actorEmail: '$user@test.com',
    callerRole: role,
    organizationId: 'org-1',
    sessionId: 'session-1',
  );

  setUp(() {
    queueRepo = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    mockAuthRepo = _MockAuthRepository();
    handler = ConfirmPeerReviewHandler(
      tenantValidator: TenantValidationService(authRepository: mockAuthRepo),
      queueRepo: queueRepo,
      reviewRepo: InMemorySanctionReviewCommandRepository(
        queueRepo: queueRepo,
        ledger: ledger,
      ),
      rbac: RbacService(),
      clock: BrazilDateTimeProvider(),
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'auditor-2',
        email: 'auditor-2@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  test('operator role is rejected (RBAC)', () async {
    await queueRepo.enqueue(peerReviewEntry());
    expect(
      () => handler.handle(cmd(user: 'auditor-2', role: UserRole.operator)),
      throwsA(isA<DomainException>()),
    );
  });

  test('requester cannot self-confirm', () async {
    await queueRepo.enqueue(peerReviewEntry());
    expect(
      () => handler.handle(cmd(user: 'auditor-1', role: UserRole.auditor)),
      throwsA(isA<DualControlSelfApprovalException>()),
    );
  });

  test('distinct second auditor seals with both signatures', () async {
    await queueRepo.enqueue(peerReviewEntry());
    await handler.handle(cmd(user: 'auditor-2', role: UserRole.auditor));

    final seal = ledger.entries.firstWhere((e) => e.type == 'VERDICT_SEALED');
    expect(seal.payload['first_reviewer_id'], 'auditor-1');
    expect(seal.payload['second_reviewer_id'], 'auditor-2');
    final entry = await queueRepo.findById('entry-pr', organizationId: 'org-1');
    expect(entry!.status, SanctionReviewStatus.applied);
  });

  test('idemp-double-confirm: second confirm on a sealed item fails', () async {
    await queueRepo.enqueue(peerReviewEntry());
    await handler.handle(cmd(user: 'auditor-2', role: UserRole.auditor));

    expect(
      () => handler.handle(cmd(user: 'auditor-2', role: UserRole.auditor)),
      throwsA(isA<DomainException>()),
    );
    expect(ledger.entries.where((e) => e.type == 'VERDICT_SEALED').length, 1);
  });
}
