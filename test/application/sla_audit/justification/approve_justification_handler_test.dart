import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/justification/approve_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/approve_justification_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/in_memory_justification_repository.dart';

void main() {
  late InMemoryJustificationRepository justificationRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ApproveJustificationHandler handler;

  final now = DateTime.utc(2026, 5, 2, 10, 0);

  ContractorJustification makePendingJustification({
    String id = 'just-001',
    String orgId = 'org-abc',
    JustificationStatus status = JustificationStatus.pending,
  }) {
    return ContractorJustification(
      id: id,
      organizationId: orgId,
      contractId: 'CTR-100',
      setId: 'SET-XYZ',
      submittedByToken: null,
      category: JustificationCategory.mechanical,
      description: 'Engine failed due to overheating on the highway route.',
      status: status,
      reviewedByUserId: null,
      reviewedAtUtc: null,
      createdAtUtc: now,
    );
  }

  ApproveJustificationCommand makeCommand({
    String orgId = 'org-abc',
    UserRole role = UserRole.operator,
  }) {
    return ApproveJustificationCommand(
      justificationId: 'just-001',
      organizationId: orgId,
      planVersion: 1,
      callerRole: role,
      callerUserId: 'user-admin-1',
      callerEmail: 'admin@tenant.com',
    );
  }

  setUp(() {
    justificationRepo = InMemoryJustificationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    handler = ApproveJustificationHandler(
      justificationRepo: justificationRepo,
      ledger: ledger,
      rbac: RbacService(),
    );
  });

  group('RBAC', () {
    test('throws DomainException for auditor role', () async {
      await justificationRepo.create(makePendingJustification());
      await expectLater(
        handler.handle(makeCommand(role: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
    });

    test('allows admin role', () async {
      await justificationRepo.create(makePendingJustification());
      await expectLater(
        handler.handle(makeCommand(role: UserRole.admin)),
        completes,
      );
    });

    test('allows operator role', () async {
      await justificationRepo.create(makePendingJustification());
      await expectLater(handler.handle(makeCommand()), completes);
    });
  });

  group('Tenant isolation', () {
    test('throws DomainException for wrong org', () async {
      await justificationRepo.create(
        makePendingJustification(orgId: 'org-abc'),
      );
      await expectLater(
        handler.handle(makeCommand(orgId: 'org-evil')),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('Idempotency guard', () {
    test('throws if already approved', () async {
      await justificationRepo.create(
        makePendingJustification(status: JustificationStatus.approved),
      );
      await expectLater(
        handler.handle(makeCommand()),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws if already rejected', () async {
      await justificationRepo.create(
        makePendingJustification(status: JustificationStatus.rejected),
      );
      await expectLater(
        handler.handle(makeCommand()),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('Happy path', () {
    test(
      'appends JUSTIFICATION_APPROVED ledger entry with actor fields',
      () async {
        await justificationRepo.create(makePendingJustification());
        await handler.handle(makeCommand());

        expect(ledger.entries.length, 1);
        expect(ledger.entries.first.type, 'JUSTIFICATION_APPROVED');
        expect(ledger.entries.first.payload['actor_id'], 'user-admin-1');
        expect(ledger.entries.first.payload['actor_email'], 'admin@tenant.com');
      },
    );

    test('updates justification status to approved', () async {
      await justificationRepo.create(makePendingJustification());
      await handler.handle(makeCommand());

      final updated = await justificationRepo.findById(
        id: 'just-001',
        organizationId: 'org-abc',
      );
      expect(updated!.isApproved, isTrue);
      expect(updated.reviewedByUserId, 'user-admin-1');
    });
  });
}
