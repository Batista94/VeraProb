import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/generate_dispute_portal_token_command.dart';
import 'package:veraprob/application/sla_audit/generate_dispute_portal_token_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late GenerateDisputePortalTokenHandler handler;
  late MockAuthRepository mockAuthRepo;

  final evidence = VerdictEvidence.create(
    clauseRef: 'no-show-rule-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5505,
    primaryEvidenceLng: -46.6333,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 6, 10, 0),
    deltaValue: 15.0,
    thresholdValue: 0.0,
    fineCents: const Money(150000),
    confidenceScore: 100,
  );

  SanctionReviewQueueEntry entry({
    SanctionReviewStatus status = SanctionReviewStatus.disputed,
  }) => SanctionReviewQueueEntry(
    id: 'entry-001',
    organizationId: 'org-1',
    ledgerEntryId: 'ledger-001',
    setId: 'set-1',
    contractId: 'contract-1',
    verdictEvidence: evidence,
    status: status,
    createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
  );

  GenerateDisputePortalTokenCommand command({
    UserRole callerRole = UserRole.auditor,
  }) => GenerateDisputePortalTokenCommand(
    queueEntryId: 'entry-001',
    createdByUserId: 'auditor-1',
    actorEmail: 'auditor@veraprob.com',
    callerRole: callerRole,
    organizationId: 'org-1',
    sessionId: 'session-1',
  );

  setUp(() {
    queueRepo = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    mockAuthRepo = MockAuthRepository();
    handler = GenerateDisputePortalTokenHandler(
      tenantValidator: TenantValidationService(authRepository: mockAuthRepo),
      queueRepo: queueRepo,
      reviewRepo: InMemorySanctionReviewCommandRepository(
        queueRepo: queueRepo,
        ledger: ledger,
      ),
      rbac: RbacService(),
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  test('mints a token for a disputed entry + logs the fact', () async {
    await queueRepo.enqueue(entry());

    final token = await handler.handle(command());

    expect(token, isNotEmpty);
    expect(
      ledger.entries
          .where((e) => e.type == 'DISPUTE_PORTAL_TOKEN_GENERATED')
          .length,
      1,
    );
  });

  test('throws Unauthorized for a non-auditor role', () async {
    // Entry IS contested + exists, so only the RBAC guard can fire — asserting
    // the message prevents a false pass from the status/not-found guards.
    await queueRepo.enqueue(entry());

    expect(
      () => handler.handle(command(callerRole: UserRole.operator)),
      throwsA(
        isA<DomainException>().having(
          (e) => e.message,
          'message',
          contains('Unauthorized'),
        ),
      ),
    );
  });

  test('throws "not contested" when the entry is still pending', () async {
    // Auditor + entry exists, so RBAC/not-found cannot fire first.
    await queueRepo.enqueue(entry(status: SanctionReviewStatus.pending));

    expect(
      () => handler.handle(command()),
      throwsA(
        isA<DomainException>().having(
          (e) => e.message,
          'message',
          contains('not contested'),
        ),
      ),
    );
  });

  test('throws "not found" when the entry is absent', () async {
    expect(
      () => handler.handle(command()),
      throwsA(
        isA<DomainException>().having(
          (e) => e.message,
          'message',
          contains('not found'),
        ),
      ),
    );
  });
}
