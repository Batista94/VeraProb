import 'package:flutter_test/flutter_test.dart';
import 'package:pactaflow/domain/sla_audit/contract.dart';
import 'package:pactaflow/domain/sla_audit/contract_status.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_contract_repository.dart';

void main() {
  late InMemoryContractRepository repo;

  setUp(() {
    repo = InMemoryContractRepository();
  });

  Contract makeContract({
    String id = 'c-1',
    String organizationId = 'org-1',
    String name = 'Contract',
    ContractStatus status = ContractStatus.draft,
  }) {
    return Contract.reconstitute(
      id: id,
      organizationId: organizationId,
      name: name,
      contractorName: 'Contractor',
      validFromUtc: DateTime.utc(2026, 1, 1),
      validUntilUtc: DateTime.utc(2026, 12, 31),
      status: status,
      createdAtUtc: DateTime.utc(2026, 1, 1),
    );
  }

  group('InMemoryContractRepository', () {
    test('save and findById — round-trip', () async {
      final contract = makeContract();
      await repo.save(contract);

      final found = await repo.findById('c-1', organizationId: 'org-1');
      expect(found, isNotNull);
      expect(found!.id, 'c-1');
      expect(found.name, 'Contract');
    });

    test('findById — returns null for unknown id', () async {
      final found = await repo.findById('unknown', organizationId: 'org-1');
      expect(found, isNull);
    });

    test('findById — tenant isolation: wrong org returns null', () async {
      await repo.save(makeContract(organizationId: 'org-A'));

      final found = await repo.findById('c-1', organizationId: 'org-B');
      expect(found, isNull);
    });

    test('save — upsert updates existing contract (status transition)', () async {
      final draft = makeContract(status: ContractStatus.draft);
      await repo.save(draft);

      final active = makeContract(status: ContractStatus.active);
      await repo.save(active);

      final found = await repo.findById('c-1', organizationId: 'org-1');
      expect(found!.status, ContractStatus.active);
    });

    test('findByOrganization — returns all contracts for org', () async {
      await repo.save(makeContract(id: 'c-1', organizationId: 'org-1', name: 'A'));
      await repo.save(makeContract(id: 'c-2', organizationId: 'org-1', name: 'B'));
      await repo.save(makeContract(id: 'c-3', organizationId: 'org-2', name: 'C'));

      final org1 = await repo.findByOrganization('org-1');
      expect(org1, hasLength(2));
      expect(org1.every((c) => c.organizationId == 'org-1'), isTrue);

      final org2 = await repo.findByOrganization('org-2');
      expect(org2, hasLength(1));
    });

    test('findByOrganization — status filter works', () async {
      await repo.save(makeContract(
          id: 'c-1', status: ContractStatus.draft));
      await repo.save(makeContract(
          id: 'c-2', status: ContractStatus.active));
      await repo.save(makeContract(
          id: 'c-3', status: ContractStatus.closed));

      final drafts = await repo.findByOrganization(
        'org-1',
        status: ContractStatus.draft,
      );
      expect(drafts, hasLength(1));
      expect(drafts.first.status, ContractStatus.draft);

      final active = await repo.findByOrganization(
        'org-1',
        status: ContractStatus.active,
      );
      expect(active, hasLength(1));
      expect(active.first.status, ContractStatus.active);
    });

    test('findByOrganization — returns empty list for org with no contracts', () async {
      final result = await repo.findByOrganization('org-empty');
      expect(result, isEmpty);
    });

    test('findByOrganization — ordering: newer contracts appear first', () async {
      final older = Contract.reconstitute(
        id: 'c-old',
        organizationId: 'org-1',
        name: 'Older',
        contractorName: 'C',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        status: ContractStatus.draft,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );
      final newer = Contract.reconstitute(
        id: 'c-new',
        organizationId: 'org-1',
        name: 'Newer',
        contractorName: 'C',
        validFromUtc: DateTime.utc(2026, 6, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        status: ContractStatus.draft,
        createdAtUtc: DateTime.utc(2026, 6, 1),
      );

      await repo.save(older);
      await repo.save(newer);

      final all = await repo.findByOrganization('org-1');
      expect(all.first.id, 'c-new');
      expect(all.last.id, 'c-old');
    });
  });
}
