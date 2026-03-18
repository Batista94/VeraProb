import 'package:flutter_test/flutter_test.dart';
import 'package:pactaflow/application/sla_audit/clone_contract_command.dart';
import 'package:pactaflow/application/sla_audit/clone_contract_handler.dart';
import 'package:pactaflow/application/sla_audit/create_contract_command.dart';
import 'package:pactaflow/application/sla_audit/create_contract_handler.dart';
import 'package:pactaflow/domain/sla_audit/contract_status.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  late InMemoryContractRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late CreateContractHandler createHandler;
  late CloneContractHandler cloneHandler;

  final validFrom = DateTime.utc(2026, 1, 1);
  final validUntil = DateTime.utc(2026, 12, 31, 23, 59, 59);
  final cloneFrom = DateTime.utc(2026, 6, 1);
  final cloneUntil = DateTime.utc(2027, 5, 31, 23, 59, 59);

  setUp(() {
    repository = InMemoryContractRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    createHandler = CreateContractHandler(
      contractRepository: repository,
      ledger: ledger,
    );
    cloneHandler = CloneContractHandler(
      contractRepository: repository,
      ledger: ledger,
    );
  });

  Future<String> createSource({String orgId = 'org-1'}) async {
    final source = await createHandler.handle(CreateContractCommand(
      organizationId: orgId,
      name: 'Contrato Original',
      contractorName: 'Trans Norte Ltda',
      description: 'Descrição original',
      validFromUtc: validFrom,
      validUntilUtc: validUntil,
    ));
    return source.id;
  }

  group('CloneContractHandler — happy path', () {
    test('creates a new draft contract with a distinct UUID', () async {
      final sourceId = await createSource();

      final clone = await cloneHandler.handle(
        CloneContractCommand(
          organizationId: 'org-1',
          sourceContractId: sourceId,
          name: 'Contrato Original (Cópia)',
          contractorName: 'Trans Norte Ltda',
          description: 'Descrição original',
        ),
        validFromUtc: cloneFrom,
        validUntilUtc: cloneUntil,
      );

      expect(clone.id, isNot(equals(sourceId)));
      expect(clone.status, ContractStatus.draft);
    });

    test('cloned contract records clonedFromContractId for audit', () async {
      final sourceId = await createSource();

      final clone = await cloneHandler.handle(
        CloneContractCommand(
          organizationId: 'org-1',
          sourceContractId: sourceId,
          name: 'Cópia',
          contractorName: 'Trans Norte Ltda',
        ),
        validFromUtc: cloneFrom,
        validUntilUtc: cloneUntil,
      );

      expect(clone.clonedFromContractId, equals(sourceId));
    });

    test('clone emits its own ContractCreatedEvent (distinct aggregate)', () async {
      final sourceId = await createSource();

      final clone = await cloneHandler.handle(
        CloneContractCommand(
          organizationId: 'org-1',
          sourceContractId: sourceId,
          name: 'Cópia',
          contractorName: 'Trans Norte Ltda',
        ),
        validFromUtc: cloneFrom,
        validUntilUtc: cloneUntil,
      );

      // Both source and clone are distinct aggregates with distinct IDs
      expect(clone.id, isNot(equals(sourceId)));
      expect(clone.clonedFromContractId, equals(sourceId));
    });

    test('clone is persisted and retrievable', () async {
      final sourceId = await createSource();

      final clone = await cloneHandler.handle(
        CloneContractCommand(
          organizationId: 'org-1',
          sourceContractId: sourceId,
          name: 'Cópia',
          contractorName: 'Trans Norte Ltda',
        ),
        validFromUtc: cloneFrom,
        validUntilUtc: cloneUntil,
      );

      final found = await repository.findById(clone.id, organizationId: 'org-1');
      expect(found, isNotNull);
      expect(found!.clonedFromContractId, equals(sourceId));
    });

    test('contracts created without cloning have null clonedFromContractId', () async {
      final sourceId = await createSource();
      final source = await repository.findById(sourceId, organizationId: 'org-1');
      expect(source!.clonedFromContractId, isNull);
    });
  });

  group('CloneContractHandler — tenant isolation (QA invariant)', () {
    test('throws DomainException when source belongs to a different org', () async {
      // Source in org-A
      final sourceId = await createSource(orgId: 'org-A');

      // Attacker in org-B tries to clone org-A's contract
      expect(
        () => cloneHandler.handle(
          CloneContractCommand(
            organizationId: 'org-B',        // different org
            sourceContractId: sourceId,
            name: 'Clone Malicioso',
            contractorName: 'Evil Corp',
          ),
          validFromUtc: cloneFrom,
          validUntilUtc: cloneUntil,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when source does not exist', () async {
      expect(
        () => cloneHandler.handle(
          const CloneContractCommand(
            organizationId: 'org-1',
            sourceContractId: 'non-existent-id',
            name: 'Clone',
            contractorName: 'Trans Norte Ltda',
          ),
          validFromUtc: cloneFrom,
          validUntilUtc: cloneUntil,
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('CloneContractHandler — domain invariants', () {
    test('throws DomainException for invalid date range (until before from)', () async {
      final sourceId = await createSource();

      expect(
        () => cloneHandler.handle(
          CloneContractCommand(
            organizationId: 'org-1',
            sourceContractId: sourceId,
            name: 'Clone',
            contractorName: 'Trans Norte Ltda',
          ),
          validFromUtc: cloneUntil,   // swapped — invalid
          validUntilUtc: cloneFrom,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty name', () async {
      final sourceId = await createSource();

      expect(
        () => cloneHandler.handle(
          CloneContractCommand(
            organizationId: 'org-1',
            sourceContractId: sourceId,
            name: '   ',            // blank
            contractorName: 'Trans Norte Ltda',
          ),
          validFromUtc: cloneFrom,
          validUntilUtc: cloneUntil,
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });
}
