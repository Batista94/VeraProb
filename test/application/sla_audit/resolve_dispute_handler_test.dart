import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_command.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ResolveDisputeHandler handler;
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;

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

  SanctionReviewQueueEntry makeDisputedEntry({
    String id = 'entry-001',
    String orgId = 'org-1',
  }) {
    return SanctionReviewQueueEntry(
      id: id,
      organizationId: orgId,
      ledgerEntryId: 'ledger-001',
      setId: 'set-1',
      contractId: 'contract-1',
      verdictEvidence: evidence,
      status: SanctionReviewStatus.disputed,
      createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
      reviewedAtUtc: DateTime.utc(2026, 4, 6, 10, 6),
      reviewedByUserId: 'auditor-disputer',
    );
  }

  /// Seeds the open SANCTION_DISPUTED ledger entry that any disputed queue
  /// entry must have (disputes=1, resolutions=0 → resolution is permitted).
  Future<void> seedOpenDispute({String queueEntryId = 'entry-001'}) async {
    await ledger.append(
      SlaLedgerEntry(
        organizationId: 'org-1',
        type: 'SANCTION_DISPUTED',
        operatorId: 'CONTRACTOR',
        setId: 'set-1',
        contractId: 'contract-1',
        planVersion: 0,
        occurredAtUtc: DateTime.utc(2026, 4, 6, 10, 6),
        payload: {'queue_entry_id': queueEntryId},
      ),
    );
  }

  ResolveDisputeCommand command({
    DisputeResolution resolution = DisputeResolution.accept,
    String? resolutionReason = 'Contractor proved force majeure.',
    UserRole callerRole = UserRole.auditor,
    String organizationId = 'org-1',
  }) {
    return ResolveDisputeCommand(
      queueEntryId: 'entry-001',
      resolution: resolution,
      resolvedByUserId: 'auditor-1',
      actorEmail: 'auditor@veraprob.com',
      resolutionReason: resolutionReason,
      callerRole: callerRole,
      organizationId: organizationId,
      sessionId: 'session-1',
    );
  }

  setUp(() {
    queueRepo = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    handler = ResolveDisputeHandler(
      tenantValidator: tenantValidator,
      queueRepo: queueRepo,
      ledger: ledger,
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

  group('ResolveDisputeHandler - RBAC', () {
    test('throws DomainException for operator role', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await expectLater(
        handler.handle(command(callerRole: UserRole.operator)),
        throwsA(isA<DomainException>()),
      );
    });

    test('allows auditor role', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await expectLater(handler.handle(command()), completes);
    });
  });

  group('ResolveDisputeHandler - Tenant isolation (INV-1/INV-22)', () {
    test('throws SovereigntyViolationException on org mismatch', () async {
      await queueRepo.enqueue(makeDisputedEntry(orgId: 'org-1'));
      await seedOpenDispute();

      await expectLater(
        handler.handle(command(organizationId: 'org-2')),
        throwsA(isA<SovereigntyViolationException>()),
      );
    });
  });

  group('ResolveDisputeHandler - Transition guard', () {
    test('throws DomainException when entry is not disputed', () async {
      await queueRepo.enqueue(
        makeDisputedEntry().copyWith(status: SanctionReviewStatus.pending),
      );
      await seedOpenDispute();

      await expectLater(
        handler.handle(command()),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('ResolveDisputeHandler - Reason validation', () {
    test('accept requires reason >= 10 chars', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await expectLater(
        handler.handle(command(resolutionReason: 'short')),
        throwsA(isA<DomainException>()),
      );
    });

    test('overturn requires reason >= 10 chars', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await expectLater(
        handler.handle(
          command(resolution: DisputeResolution.overturn, resolutionReason: ''),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('retract permits a null reason', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await expectLater(
        handler.handle(
          command(
            resolution: DisputeResolution.retract,
            resolutionReason: null,
          ),
        ),
        completes,
      );
    });
  });

  group('ResolveDisputeHandler - accept (disputed -> rejected)', () {
    test('appends DISPUTE_ACCEPTED then sets status rejected', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await handler.handle(command(resolution: DisputeResolution.accept));

      final resolution = ledger.entries.last;
      expect(resolution.type, 'DISPUTE_ACCEPTED');
      expect(resolution.payload['queue_entry_id'], 'entry-001');
      expect(resolution.payload['resolution_reason'], isNotNull);

      final entry = await queueRepo.findById(
        'entry-001',
        organizationId: 'org-1',
      );
      expect(entry!.status, SanctionReviewStatus.rejected);
      // Reason persisted to queue for the Concluídos tab.
      expect(entry.rejectionReason, 'Contractor proved force majeure.');
    });
  });

  group('ResolveDisputeHandler - overturn (disputed -> applied)', () {
    test('appends DISPUTE_OVERTURNED then sets status applied', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();

      await handler.handle(command(resolution: DisputeResolution.overturn));

      final resolution = ledger.entries.last;
      expect(resolution.type, 'DISPUTE_OVERTURNED');

      final entry = await queueRepo.findById(
        'entry-001',
        organizationId: 'org-1',
      );
      expect(entry!.status, SanctionReviewStatus.applied);
    });
  });

  group('ResolveDisputeHandler - retract (disputed -> pending)', () {
    test(
      'appends DISPUTE_RETRACTED, clears review fields, keeps reviewedBy',
      () async {
        await queueRepo.enqueue(makeDisputedEntry());
        await seedOpenDispute();

        await handler.handle(
          command(
            resolution: DisputeResolution.retract,
            resolutionReason: null,
          ),
        );

        final resolution = ledger.entries.last;
        expect(resolution.type, 'DISPUTE_RETRACTED');

        final entry = await queueRepo.findById(
          'entry-001',
          organizationId: 'org-1',
        );
        expect(entry!.status, SanctionReviewStatus.pending);
        expect(entry.reviewedAtUtc, isNull);
        expect(entry.rejectionReason, isNull);
        // Forensic honesty: the original disputer is preserved.
        expect(entry.reviewedByUserId, 'auditor-disputer');
      },
    );
  });

  group('ResolveDisputeHandler - Idempotent concurrency guard', () {
    test('throws IdempotencyProcessingException when current dispute already '
        'resolved in the ledger', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();
      // A concurrent auditor already appended the resolution.
      await ledger.append(
        SlaLedgerEntry(
          organizationId: 'org-1',
          type: 'DISPUTE_ACCEPTED',
          operatorId: 'auditor-other',
          setId: 'set-1',
          contractId: 'contract-1',
          planVersion: 0,
          occurredAtUtc: DateTime.utc(2026, 4, 6, 10, 7),
          payload: {'queue_entry_id': 'entry-001'},
        ),
      );

      await expectLater(
        handler.handle(command()),
        throwsA(isA<IdempotencyProcessingException>()),
      );
    });

    test('does not append a second ledger entry when blocked', () async {
      await queueRepo.enqueue(makeDisputedEntry());
      await seedOpenDispute();
      await ledger.append(
        SlaLedgerEntry(
          organizationId: 'org-1',
          type: 'DISPUTE_OVERTURNED',
          operatorId: 'auditor-other',
          setId: 'set-1',
          contractId: 'contract-1',
          planVersion: 0,
          occurredAtUtc: DateTime.utc(2026, 4, 6, 10, 7),
          payload: {'queue_entry_id': 'entry-001'},
        ),
      );
      final before = ledger.entries.length;

      await handler.handle(command()).catchError((_) {});

      expect(ledger.entries.length, before);
    });
  });
}
