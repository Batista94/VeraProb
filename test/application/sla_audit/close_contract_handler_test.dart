import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/create_contract_command.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/application/sla_audit/close_contract_command.dart';
import 'package:veraprob/application/sla_audit/close_contract_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  late InMemoryContractRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late CreateContractHandler createHandler;
  late CloseContractHandler closeHandler;

  setUp(() {
    repository = InMemoryContractRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    createHandler = CreateContractHandler(
      contractRepository: repository,
      ledger: ledger,
    );
    closeHandler = CloseContractHandler(
      contractRepository: repository,
      ledger: ledger,
      rbac: RbacService(),
    );
  });

  group('CloseContractHandler', () {
    test(
      'closes a draft contract — appends CONTRACT_CLOSED to ledger',
      () async {
        final created = await createHandler.handle(
          CreateContractCommand(
            organizationId: 'org-1',
            name: 'Contrato A',
            contractorName: 'Empresa A',
            validFromUtc: DateTime.utc(2026, 1, 1),
            validUntilUtc: DateTime.utc(2026, 12, 31),
          ),
        );

        final closed = await closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: created.id,
            closedByUserId: 'user-1',
            reason: 'Cancelled',
            callerRole: UserRole.operator,
          ),
        );

        expect(closed.status, ContractStatus.closed);
        expect(closed.closedByUserId, 'user-1');
        expect(closed.closeReason, 'Cancelled');
        expect(closed.closedAtUtc, isNotNull);

        // Persisted state updated
        final found = await repository.findById(
          created.id,
          organizationId: 'org-1',
        );
        expect(found!.status, ContractStatus.closed);

        // Ledger: CONTRACT_CREATED + CONTRACT_CLOSED
        expect(ledger.entries, hasLength(2));
        expect(ledger.entries.first.type, 'CONTRACT_CREATED');
        expect(ledger.entries.last.type, 'CONTRACT_CLOSED');
      },
    );

    test('throws DomainException when contract not found', () async {
      expect(
        () => closeHandler.handle(
          const CloseContractCommand(
            organizationId: 'org-1',
            contractId: 'non-existent',
            closedByUserId: 'user-1',
            reason: 'Done',
            callerRole: UserRole.operator,
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'throws DomainException for wrong organization (tenant isolation)',
      () async {
        final created = await createHandler.handle(
          CreateContractCommand(
            organizationId: 'org-A',
            name: 'Contract A',
            contractorName: 'Empresa A',
            validFromUtc: DateTime.utc(2026, 1, 1),
            validUntilUtc: DateTime.utc(2026, 12, 31),
          ),
        );

        expect(
          () => closeHandler.handle(
            CloseContractCommand(
              organizationId: 'org-B',
              contractId: created.id,
              closedByUserId: 'user-1',
              reason: 'Done',
              callerRole: UserRole.operator,
            ),
          ),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      'throws DomainException when closing an already-closed contract',
      () async {
        final created = await createHandler.handle(
          CreateContractCommand(
            organizationId: 'org-1',
            name: 'Contract B',
            contractorName: 'Empresa B',
            validFromUtc: DateTime.utc(2026, 1, 1),
            validUntilUtc: DateTime.utc(2026, 12, 31),
          ),
        );

        await closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: created.id,
            closedByUserId: 'user-1',
            reason: 'First close',
            callerRole: UserRole.operator,
          ),
        );

        expect(
          () => closeHandler.handle(
            CloseContractCommand(
              organizationId: 'org-1',
              contractId: created.id,
              closedByUserId: 'user-1',
              reason: 'Second close',
              callerRole: UserRole.operator,
            ),
          ),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test('throws DomainException for empty closedByUserId', () async {
      final created = await createHandler.handle(
        CreateContractCommand(
          organizationId: 'org-1',
          name: 'Contract C',
          contractorName: 'Empresa C',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ),
      );

      expect(
        () => closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: created.id,
            closedByUserId: '',
            reason: 'Done',
            callerRole: UserRole.operator,
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for blank reason', () async {
      final created = await createHandler.handle(
        CreateContractCommand(
          organizationId: 'org-1',
          name: 'Contract D',
          contractorName: 'Empresa D',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ),
      );

      expect(
        () => closeHandler.handle(
          CloseContractCommand(
            organizationId: 'org-1',
            contractId: created.id,
            closedByUserId: 'user-1',
            reason: '   ',
            callerRole: UserRole.operator,
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    // ── RBAC ──────────────────────────────────────────────────────────────

    test('RBAC: auditor is rejected before any I/O', () async {
      expect(
        () => closeHandler.handle(
          const CloseContractCommand(
            organizationId: 'org-1',
            contractId: 'any-id',
            closedByUserId: 'user-auditor',
            reason: 'Attempt',
            callerRole: UserRole.auditor,
          ),
        ),
        throwsA(isA<DomainException>()),
      );
      // Ledger must remain empty — RBAC check fires before repository I/O
      expect(ledger.entries, isEmpty);
    });

    test('RBAC: operator is authorized to close contracts', () async {
      final created = await createHandler.handle(
        CreateContractCommand(
          organizationId: 'org-1',
          name: 'Contract E',
          contractorName: 'Empresa E',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ),
      );

      final closed = await closeHandler.handle(
        CloseContractCommand(
          organizationId: 'org-1',
          contractId: created.id,
          closedByUserId: 'user-operator',
          reason: 'Closed by operator',
          callerRole: UserRole.operator,
        ),
      );

      expect(closed.status, ContractStatus.closed);
    });

    test('RBAC: admin is authorized to close contracts', () async {
      final created = await createHandler.handle(
        CreateContractCommand(
          organizationId: 'org-1',
          name: 'Contract F',
          contractorName: 'Empresa F',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ),
      );

      final closed = await closeHandler.handle(
        CloseContractCommand(
          organizationId: 'org-1',
          contractId: created.id,
          closedByUserId: 'user-admin',
          reason: 'Closed by admin',
          callerRole: UserRole.admin,
        ),
      );

      expect(closed.status, ContractStatus.closed);
    });
  });
}
