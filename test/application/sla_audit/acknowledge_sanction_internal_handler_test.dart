import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/acknowledge_sanction_internal_command.dart';
import 'package:veraprob/application/sla_audit/acknowledge_sanction_internal_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_acknowledgement_command_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sanction_review_queue_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemorySanctionReviewQueueRepository queueRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late AcknowledgeSanctionInternalHandler handler;
  late MockAuthRepository mockAuthRepo;

  final evidence = VerdictEvidence.create(
    clauseRef: 'rule-1',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5,
    primaryEvidenceLng: -46.6,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 4, 6, 10),
    deltaValue: 15,
    thresholdValue: 0,
    fineCents: const Money(150000),
    confidenceScore: 100,
  );

  SanctionReviewQueueEntry entry(SanctionReviewStatus status) =>
      SanctionReviewQueueEntry(
        id: 'entry-001',
        organizationId: 'org-1',
        ledgerEntryId: 'ledger-001',
        setId: 'set-1',
        contractId: 'contract-1',
        verdictEvidence: evidence,
        status: status,
        createdAtUtc: DateTime.utc(2026, 4, 6, 10, 5),
      );

  AcknowledgeSanctionInternalCommand cmd({UserRole role = UserRole.admin}) =>
      AcknowledgeSanctionInternalCommand(
        organizationId: 'org-1',
        queueEntryId: 'entry-001',
        acknowledgedByUserId: 'user-1',
        notes: 'aceito por telefone',
        callerRole: role,
        sessionId: 'session-1',
      );

  setUp(() {
    queueRepo = InMemorySanctionReviewQueueRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    mockAuthRepo = MockAuthRepository();
    handler = AcknowledgeSanctionInternalHandler(
      tenantValidator: TenantValidationService(authRepository: mockAuthRepo),
      queueRepo: queueRepo,
      ackRepo: InMemorySanctionAcknowledgementCommandRepository(
        queueRepo: queueRepo,
        ledger: ledger,
        clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12)),
      ),
      rbac: RbacService(),
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'admin@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  test(
    'admin acknowledges an applied sanction → acknowledged + ledger fact',
    () async {
      await queueRepo.enqueue(entry(SanctionReviewStatus.applied));

      final id = await handler.handle(cmd());

      expect(id, isNotEmpty);
      final updated = await queueRepo.findById(
        'entry-001',
        organizationId: 'org-1',
      );
      expect(updated!.status, SanctionReviewStatus.acknowledged);
      expect(
        ledger.entries.where((e) => e.type == 'SANCTION_ACKNOWLEDGED').length,
        1,
      );
    },
  );

  test('operator role is rejected (RBAC fail-fast)', () async {
    await queueRepo.enqueue(entry(SanctionReviewStatus.applied));
    expect(
      () => handler.handle(cmd(role: UserRole.operator)),
      throwsA(isA<DomainException>()),
    );
  });

  test('non-applied sanction cannot be acknowledged', () async {
    await queueRepo.enqueue(entry(SanctionReviewStatus.pending));
    expect(() => handler.handle(cmd()), throwsA(isA<DomainException>()));
  });

  test('missing entry is rejected', () async {
    expect(() => handler.handle(cmd()), throwsA(isA<DomainException>()));
  });
}
