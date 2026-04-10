import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/contract_events.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

void main() {
  final nowUtc = DateTime.parse('2026-04-08T12:00:00Z').toUtc();

  // ── Shared helpers ─────────────────────────────────────────

  Contract makeContract({
    String organizationId = 'org-1',
    String name = 'Contrato A',
    String contractorName = 'Empresa XYZ',
    String? description,
    DateTime? validFrom,
    DateTime? validUntil,
    int penaltyMultiplierBps = 10000,
  }) {
    final from = validFrom ?? DateTime.utc(2026, 1, 1);
    final until = validUntil ?? DateTime.utc(2026, 12, 31);
    return Contract.create(
      organizationId: organizationId,
      name: name,
      contractorName: contractorName,
      description: description,
      validFromUtc: from,
      validUntilUtc: until,
      penaltyMultiplierBps: penaltyMultiplierBps,
      nowUtc: nowUtc,
    );
  }

  // ── Contract.create ────────────────────────────────────────

  group('Contract.create', () {
    test('creates aggregate in draft status', () {
      final contract = makeContract();

      expect(contract.status, ContractStatus.draft);
      expect(contract.isDraft, isTrue);
      expect(contract.isActive, isFalse);
      expect(contract.isClosed, isFalse);
    });

    test('generates non-empty UUID id', () {
      final c1 = makeContract();
      final c2 = makeContract();

      expect(c1.id, isNotEmpty);
      expect(c2.id, isNotEmpty);
      expect(c1.id, isNot(equals(c2.id)));
    });

    test('preserves all supplied fields', () {
      final from = DateTime.utc(2026, 3, 1);
      final until = DateTime.utc(2026, 9, 30);
      final contract = makeContract(
        organizationId: 'org-42',
        name: 'Rota Norte',
        contractorName: 'Trans Norte Ltda',
        description: 'Contrato rota norte',
        validFrom: from,
        validUntil: until,
      );

      expect(contract.organizationId, 'org-42');
      expect(contract.name, 'Rota Norte');
      expect(contract.contractorName, 'Trans Norte Ltda');
      expect(contract.description, 'Contrato rota norte');
      expect(contract.validFromUtc, from);
      expect(contract.validUntilUtc, until);
    });

    test('sets nullable timestamps to null on creation', () {
      final contract = makeContract();

      expect(contract.activatedAtUtc, isNull);
      expect(contract.closedAtUtc, isNull);
      expect(contract.closedByUserId, isNull);
      expect(contract.closeReason, isNull);
    });

    test('emits exactly one ContractCreatedEvent', () {
      final contract = makeContract();

      expect(contract.domainEvents, hasLength(1));
      expect(contract.domainEvents.first, isA<ContractCreatedEvent>());

      final event = contract.domainEvents.first as ContractCreatedEvent;
      expect(event.contractId, contract.id);
      expect(event.organizationId, contract.organizationId);
      expect(event.name, contract.name);
    });

    test('throws DomainException for empty organizationId', () {
      expect(
        () => makeContract(organizationId: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for blank name', () {
      expect(() => makeContract(name: '   '), throwsA(isA<DomainException>()));
    });

    test('throws DomainException for blank contractorName', () {
      expect(
        () => makeContract(contractorName: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when validUntil is not after validFrom', () {
      final d = DateTime.utc(2026, 6, 1);
      expect(
        () => makeContract(validFrom: d, validUntil: d),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => makeContract(
          validFrom: DateTime.utc(2026, 6, 2),
          validUntil: DateTime.utc(2026, 6, 1),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── Contract.reconstitute ──────────────────────────────────

  group('Contract.reconstitute', () {
    test('does NOT emit domain events', () {
      final contract = Contract.reconstitute(
        id: 'existing-id',
        organizationId: 'org-1',
        name: 'Contract B',
        contractorName: 'Empresa B',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        status: ContractStatus.active,
        createdAtUtc: DateTime.utc(2026, 1, 1),
        penaltyMultiplierBps: 10000,
        activatedAtUtc: DateTime.utc(2026, 2, 1),
      );

      expect(contract.domainEvents, isEmpty);
    });

    test('restores all fields including lifecycle timestamps', () {
      final created = DateTime.utc(2026, 1, 1);
      final activated = DateTime.utc(2026, 2, 1);
      final closed = DateTime.utc(2026, 11, 30);

      final contract = Contract.reconstitute(
        id: 'c-123',
        organizationId: 'org-5',
        name: 'Contract C',
        contractorName: 'Empresa C',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        status: ContractStatus.closed,
        createdAtUtc: created,
        activatedAtUtc: activated,
        closedAtUtc: closed,
        closedByUserId: 'user-9',
        closeReason: 'Contract ended.',
        penaltyMultiplierBps: 10000,
      );

      expect(contract.id, 'c-123');
      expect(contract.status, ContractStatus.closed);
      expect(contract.createdAtUtc, created);
      expect(contract.activatedAtUtc, activated);
      expect(contract.closedAtUtc, closed);
      expect(contract.closedByUserId, 'user-9');
      expect(contract.closeReason, 'Contract ended.');
    });
  });

  // ── Contract.activate ─────────────────────────────────────

  group('activate()', () {
    test('draft → active transition returns new instance', () {
      final draft = makeContract();
      final active = draft.activate(nowUtc: nowUtc);

      expect(active.status, ContractStatus.active);
      expect(active.isActive, isTrue);
      expect(active.id, draft.id); // same identity
      expect(active.activatedAtUtc, isNotNull);
    });

    test('original draft instance is not mutated', () {
      final draft = makeContract();
      draft.activate(nowUtc: nowUtc);

      expect(draft.status, ContractStatus.draft);
      expect(draft.activatedAtUtc, isNull);
    });

    test('emits ContractActivatedEvent', () {
      final active = makeContract().activate(nowUtc: nowUtc);

      expect(active.domainEvents, hasLength(1));
      expect(active.domainEvents.first, isA<ContractActivatedEvent>());

      final event = active.domainEvents.first as ContractActivatedEvent;
      expect(event.contractId, active.id);
    });

    test('throws DomainException if already active', () {
      final active = makeContract().activate(nowUtc: nowUtc);

      expect(
        () => active.activate(nowUtc: nowUtc),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException if closed', () {
      final closed = makeContract()
          .activate(nowUtc: nowUtc)
          .close(closedByUserId: 'user-1', reason: 'Done', nowUtc: nowUtc);

      expect(
        () => closed.activate(nowUtc: nowUtc),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── Contract.close ────────────────────────────────────────

  group('close()', () {
    test('active → closed transition', () {
      final active = makeContract().activate(nowUtc: nowUtc);
      final closed = active.close(
        closedByUserId: 'user-1',
        reason: 'Done',
        nowUtc: nowUtc,
      );

      expect(closed.status, ContractStatus.closed);
      expect(closed.isClosed, isTrue);
      expect(closed.closedAtUtc, isNotNull);
      expect(closed.closedByUserId, 'user-1');
      expect(closed.closeReason, 'Done');
    });

    test('draft → closed transition is allowed', () {
      final draft = makeContract();
      final closed = draft.close(
        closedByUserId: 'admin',
        reason: 'Cancelled',
        nowUtc: nowUtc,
      );

      expect(closed.status, ContractStatus.closed);
    });

    test('original instance is not mutated', () {
      final active = makeContract().activate(nowUtc: nowUtc);
      active.close(closedByUserId: 'user-1', reason: 'Done', nowUtc: nowUtc);

      expect(active.status, ContractStatus.active);
      expect(active.closedAtUtc, isNull);
    });

    test('emits ContractClosedEvent', () {
      final closed = makeContract()
          .activate(nowUtc: nowUtc)
          .close(closedByUserId: 'user-1', reason: 'Done', nowUtc: nowUtc);

      expect(closed.domainEvents, hasLength(1));
      expect(closed.domainEvents.first, isA<ContractClosedEvent>());

      final event = closed.domainEvents.first as ContractClosedEvent;
      expect(event.contractId, closed.id);
      expect(event.closedByUserId, 'user-1');
    });

    test('throws DomainException if already closed', () {
      final closed = makeContract()
          .activate(nowUtc: nowUtc)
          .close(closedByUserId: 'user-1', reason: 'Done', nowUtc: nowUtc);

      expect(
        () => closed.close(
          closedByUserId: 'user-1',
          reason: 'Again',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty closedByUserId', () {
      final active = makeContract().activate(nowUtc: nowUtc);

      expect(
        () => active.close(closedByUserId: '', reason: 'Done', nowUtc: nowUtc),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for blank reason', () {
      final active = makeContract().activate(nowUtc: nowUtc);

      expect(
        () => active.close(
          closedByUserId: 'user-1',
          reason: '   ',
          nowUtc: nowUtc,
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── assertCanReceivePlan ───────────────────────────────────

  group('assertCanReceivePlan()', () {
    test('does not throw for draft', () {
      final contract = makeContract();
      expect(() => contract.assertCanReceivePlan(), returnsNormally);
    });

    test('does not throw for active', () {
      final active = makeContract().activate(nowUtc: nowUtc);
      expect(() => active.assertCanReceivePlan(), returnsNormally);
    });

    test('throws DomainException for closed', () {
      final closed = makeContract()
          .activate(nowUtc: nowUtc)
          .close(closedByUserId: 'user-1', reason: 'Done', nowUtc: nowUtc);

      expect(
        () => closed.assertCanReceivePlan(),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── Equatable ─────────────────────────────────────────────

  group('Equatable', () {
    test('two reconstituted contracts with same data are equal', () {
      final c1 = Contract.reconstitute(
        id: 'same-id',
        organizationId: 'org-1',
        name: 'Name',
        contractorName: 'Contractor',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        status: ContractStatus.draft,
        createdAtUtc: DateTime.utc(2026, 1, 1),
        penaltyMultiplierBps: 10000,
      );
      final c2 = Contract.reconstitute(
        id: 'same-id',
        organizationId: 'org-1',
        name: 'Name',
        contractorName: 'Contractor',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        status: ContractStatus.draft,
        createdAtUtc: DateTime.utc(2026, 1, 1),
        penaltyMultiplierBps: 10000,
      );

      expect(c1, equals(c2));
    });

    test('two different contracts are not equal', () {
      final c1 = makeContract(name: 'Alpha');
      final c2 = makeContract(name: 'Beta');

      expect(c1, isNot(equals(c2)));
    });
  });
}
