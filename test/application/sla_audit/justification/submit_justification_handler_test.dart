import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/in_memory_justification_repository.dart';
import 'package:veraprob/infrastructure/local_fact_db/in_memory_local_fact_queue_repository.dart';
import '../../../mocks/fake_date_time_provider.dart';

void main() {
  late InMemoryJustificationRepository justificationRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemoryLocalFactQueueRepository factQueue;
  late SubmitJustificationHandler handler;

  SubmitJustificationCommand makeCommand({
    UserRole? role = UserRole.operator,
    String? tokenId,
    String description = 'Engine failed due to overheating on the route.',
  }) {
    return SubmitJustificationCommand(
      organizationId: 'org-abc',
      contractId: 'CTR-100',
      setId: 'SET-XYZ',
      planVersion: 1,
      category: 'MECHANICAL',
      description: description,
      callerRole: role,
      callerUserId: 'user-op-1',
      callerEmail: 'op@tenant.com',
      submittedByTokenId: tokenId,
      evidenceHashes: const [],
    );
  }

  setUp(() {
    final now = DateTime(2026, 4, 8, 10, 0, 0);
    final clockProvider = FakeDateTimeProvider(now);
    justificationRepo = InMemoryJustificationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    factQueue = InMemoryLocalFactQueueRepository(clockProvider);
    handler = SubmitJustificationHandler(
      justificationRepo: justificationRepo,
      ledger: ledger,
      factQueue: factQueue,
      rbac: RbacService(),
      clock: clockProvider,
    );
  });

  group('RBAC', () {
    test('throws DomainException for auditor role', () async {
      await expectLater(
        handler.handle(makeCommand(role: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for contractorViewer role', () async {
      await expectLater(
        handler.handle(makeCommand(role: UserRole.contractorViewer)),
        throwsA(isA<DomainException>()),
      );
    });

    test('allows operator role', () async {
      await expectLater(handler.handle(makeCommand()), completes);
    });

    test('allows admin role', () async {
      await expectLater(
        handler.handle(makeCommand(role: UserRole.admin)),
        completes,
      );
    });

    test('token path (null role) is allowed', () async {
      await expectLater(
        handler.handle(makeCommand(role: null, tokenId: 'tok-123')),
        completes,
      );
    });
  });

  group('Validation', () {
    test('throws on description shorter than 20 chars', () async {
      await expectLater(
        handler.handle(makeCommand(description: 'Too short.')),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on invalid category', () async {
      const cmd = SubmitJustificationCommand(
        organizationId: 'org-abc',
        contractId: 'CTR-100',
        setId: 'SET-XYZ',
        planVersion: 1,
        category: 'INVALID_CAT',
        description: 'Engine failed due to overheating on the route.',
        callerRole: UserRole.operator,
        callerUserId: 'user-op-1',
        callerEmail: 'op@tenant.com',
        submittedByTokenId: null,
        evidenceHashes: [],
      );
      await expectLater(handler.handle(cmd), throwsA(isA<DomainException>()));
    });
  });

  group('Happy path', () {
    test('persists justification with PENDING status', () async {
      await handler.handle(makeCommand());

      final list = await justificationRepo.listByOrg(organizationId: 'org-abc');
      expect(list.length, 1);
      expect(list.first.status.dbValue, 'PENDING');
      expect(list.first.contractId, 'CTR-100');
      expect(list.first.setId, 'SET-XYZ');
    });

    test('appends JUSTIFICATION_SUBMITTED ledger entry', () async {
      await handler.handle(makeCommand());
      expect(ledger.entries.length, 1);
      expect(ledger.entries.first.type, 'JUSTIFICATION_SUBMITTED');
    });

    test('enqueues PendingFact for offline resilience', () async {
      await handler.handle(makeCommand());
      final pending = await factQueue.getPending();
      expect(pending.length, 1);
    });

    test(
      'same command twice does not duplicate (idempotency via factId)',
      () async {
        await handler.handle(makeCommand());
        await handler.handle(makeCommand());
        final pending = await factQueue.getPending();
        expect(pending.length, 1); // second enqueue is no-op
      },
    );
  });
}
