// Regression + adversarial domain tests for [Contract].
//
// Skill Insight — QA & Security Lead (Paranoid Protector)
// Invariants guarded:
//   INV-3  (Ledger Integrity): version=0 is the "never persisted" sentinel.
//   INV-10 (Typed Exceptions): state violations -> DomainException only.
//   INV-14 (Transport-agnostic Core): domain must not know about DB versioning.
//
// CT04 regression guard: if create() ever returns version != 0 again,
// save() will dispatch INSERT on a contract that the DB already has — duplicate key.

import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_events.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

void main() {
  final kNow = DateTime.parse('2026-06-06T10:00:00Z');
  final kFrom = DateTime.utc(2026, 1, 1);
  final kUntil = DateTime.utc(2026, 12, 31);

  Contract draft({String org = 'org-1'}) => Contract.create(
    organizationId: org,
    name: 'Contrato de Teste',
    contractorName: 'Empresa LTDA',
    validFromUtc: kFrom,
    validUntilUtc: kUntil,
    nowUtc: kNow,
  );

  Contract persisted({
    int version = 1,
    ContractStatus status = ContractStatus.draft,
  }) => Contract.reconstitute(
    id: 'fixed-id-001',
    version: version,
    organizationId: 'org-1',
    name: 'Contrato Persistido',
    contractorName: 'Empresa LTDA',
    validFromUtc: kFrom,
    validUntilUtc: kUntil,
    status: status,
    createdAtUtc: kNow,
    penaltyMultiplierBps: 10000,
  );

  // ── REG-DOM: Version sentinel ──────────────────────────────────────────────

  group('REG-DOM-1/2: Contract.create() version sentinel', () {
    // REGRESSION GUARD (CT04):
    // Before fix, create() returned version=1. The DB also defaults to 1 on INSERT.
    // DeclareContractualPlanHandler loaded the saved contract (version=1), called
    // activate() (preserved version=1), then save() dispatched to _create() (INSERT)
    // → duplicate PK on the contracts table.
    //
    // This test MUST stay green. If it fails, CT04 will fail in production.

    test(
      'REG-DOM-1: create() returns version=0 — sentinel for "never persisted"',
      () {
        expect(
          draft().version,
          0,
          reason:
              'version=0 signals the repo to use INSERT. '
              'Any other value re-introduces the CT04 duplicate key bug.',
        );
      },
    );

    test(
      'REG-DOM-2: two create() calls produce distinct IDs both at version=0',
      () {
        final c1 = draft();
        final c2 = draft();
        expect(c1.version, 0);
        expect(c2.version, 0);
        expect(c1.id, isNot(equals(c2.id)));
      },
    );
  });

  group('REG-DOM-3/4: Contract.createClone() version sentinel', () {
    test(
      'REG-DOM-3: createClone() returns version=0 (unpersisted sentinel)',
      () {
        final clone = Contract.createClone(
          organizationId: 'org-1',
          name: 'Clone',
          contractorName: 'Empresa LTDA',
          validFromUtc: kFrom,
          validUntilUtc: kUntil,
          clonedFromContractId: 'source-id-abc',
          nowUtc: kNow,
        );
        expect(clone.version, 0);
      },
    );

    test('REG-DOM-4: createClone() records clonedFromContractId', () {
      final clone = Contract.createClone(
        organizationId: 'org-1',
        name: 'Clone',
        contractorName: 'Empresa LTDA',
        validFromUtc: kFrom,
        validUntilUtc: kUntil,
        clonedFromContractId: 'source-uuid-xyz',
        nowUtc: kNow,
      );
      expect(clone.clonedFromContractId, 'source-uuid-xyz');
    });
  });

  group('REG-DOM-5/7: Contract.reconstitute() version preservation', () {
    test('REG-DOM-5: reconstitute() preserves version=1 (first DB write)', () {
      expect(persisted(version: 1).version, 1);
    });

    test(
      'REG-DOM-6: reconstitute() preserves arbitrary DB version (e.g. 42)',
      () {
        expect(persisted(version: 42).version, 42);
      },
    );

    test(
      'REG-DOM-7: reconstitute() emits no domain events (projection, not creation)',
      () {
        expect(persisted().domainEvents, isEmpty);
      },
    );
  });

  group('REG-DOM-8/12: State transitions preserve version', () {
    // The DB trigger increments version on each UPDATE.
    // Domain must pass version through unchanged — it is NOT the domain's job.

    test(
      'REG-DOM-8: activate() preserves version from DB-loaded aggregate',
      () {
        final activated = persisted(version: 3).activate(nowUtc: kNow);
        expect(
          activated.version,
          3,
          reason:
              'Domain must not increment version. '
              'Only the DB trigger does this on UPDATE.',
        );
      },
    );

    test('REG-DOM-9: close() preserves version', () {
      final closed = persisted(version: 5, status: ContractStatus.active).close(
        closedByUserId: 'user-1',
        reason: 'Encerramento contratual',
        nowUtc: kNow,
      );
      expect(closed.version, 5);
    });

    test('REG-DOM-10: submitForApproval() preserves version', () {
      final submitted = persisted(
        version: 2,
      ).submitForApproval(reviewToken: 'tok-abc', nowUtc: kNow);
      expect(submitted.version, 2);
    });

    test('REG-DOM-11: acceptByContractor() preserves version', () {
      final accepted = persisted(
        version: 4,
        status: ContractStatus.awaitingContractorAcceptance,
      ).acceptByContractor(reviewToken: 'tok-abc', nowUtc: kNow);
      expect(accepted.version, 4);
    });

    test('REG-DOM-12: create() then activate() keeps version=0 '
        '(pre-save transition must not change sentinel)', () {
      final activated = draft().activate(nowUtc: kNow);
      expect(
        activated.version,
        0,
        reason:
            'A pre-save transition must not bump version. '
            'Repository must still dispatch INSERT, not UPDATE.',
      );
    });
  });

  // ── ADV-DOM: Boundary enforcement ─────────────────────────────────────────

  group('ADV-DOM: Contract.create() input boundary', () {
    test('ADV-DOM-1: empty organizationId throws DomainException', () {
      expect(
        () => Contract.create(
          organizationId: '',
          name: 'Nome',
          contractorName: 'Empresa',
          validFromUtc: kFrom,
          validUntilUtc: kUntil,
          nowUtc: kNow,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('ADV-DOM-2: whitespace-only name throws DomainException', () {
      expect(
        () => Contract.create(
          organizationId: 'org-1',
          name: '   ',
          contractorName: 'Empresa',
          validFromUtc: kFrom,
          validUntilUtc: kUntil,
          nowUtc: kNow,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('ADV-DOM-3: empty contractorName throws DomainException', () {
      expect(
        () => Contract.create(
          organizationId: 'org-1',
          name: 'Nome',
          contractorName: '',
          validFromUtc: kFrom,
          validUntilUtc: kUntil,
          nowUtc: kNow,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('ADV-DOM-4: validUntil before validFrom throws DomainException', () {
      expect(
        () => Contract.create(
          organizationId: 'org-1',
          name: 'Nome',
          contractorName: 'Empresa',
          validFromUtc: DateTime.utc(2026, 12, 31),
          validUntilUtc: DateTime.utc(2026, 1, 1),
          nowUtc: kNow,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('ADV-DOM-5: validUntil equals validFrom throws DomainException', () {
      final date = DateTime.utc(2026, 6, 1);
      expect(
        () => Contract.create(
          organizationId: 'org-1',
          name: 'Nome',
          contractorName: 'Empresa',
          validFromUtc: date,
          validUntilUtc: date,
          nowUtc: kNow,
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('ADV-DOM: State transition guards', () {
    test('ADV-DOM-6: activate() on active contract throws DomainException', () {
      expect(
        () => persisted(status: ContractStatus.active).activate(nowUtc: kNow),
        throwsA(isA<DomainException>()),
      );
    });

    test('ADV-DOM-7: activate() on closed contract throws DomainException', () {
      expect(
        () => persisted(status: ContractStatus.closed).activate(nowUtc: kNow),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'ADV-DOM-8: close() on already closed throws DomainException (terminal state)',
      () {
        expect(
          () => persisted(
            status: ContractStatus.closed,
          ).close(closedByUserId: 'user-1', reason: 'Tentativa', nowUtc: kNow),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test('ADV-DOM-9: close() with empty reason throws DomainException', () {
      expect(
        () => persisted(
          status: ContractStatus.active,
        ).close(closedByUserId: 'user-1', reason: '', nowUtc: kNow),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'ADV-DOM-10: close() with empty closedByUserId throws DomainException',
      () {
        expect(
          () => persisted(
            status: ContractStatus.active,
          ).close(closedByUserId: '', reason: 'Encerramento', nowUtc: kNow),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      'ADV-DOM-11: submitForApproval() on active contract throws DomainException',
      () {
        expect(
          () => persisted(
            status: ContractStatus.active,
          ).submitForApproval(reviewToken: 'tok', nowUtc: kNow),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      'ADV-DOM-12: acceptByContractor() on draft throws DomainException',
      () {
        expect(
          () => draft().acceptByContractor(reviewToken: 'tok', nowUtc: kNow),
          throwsA(isA<DomainException>()),
        );
      },
    );
  });

  group('ADV-DOM: assertCanReceivePlan() guard', () {
    test('ADV-DOM-13: closed contract rejects plan declaration', () {
      expect(
        () => persisted(status: ContractStatus.closed).assertCanReceivePlan(),
        throwsA(isA<DomainException>()),
      );
    });

    test('ADV-DOM-14: awaiting acceptance rejects plan declaration', () {
      expect(
        () => persisted(
          status: ContractStatus.awaitingContractorAcceptance,
        ).assertCanReceivePlan(),
        throwsA(isA<DomainException>()),
      );
    });

    test('ADV-DOM-15: draft accepts plan declaration (no throw)', () {
      expect(() => draft().assertCanReceivePlan(), returnsNormally);
    });

    test('ADV-DOM-16: active contract accepts plan declaration (no throw)', () {
      expect(
        () => persisted(status: ContractStatus.active).assertCanReceivePlan(),
        returnsNormally,
      );
    });
  });

  // ── Domain events ──────────────────────────────────────────────────────────

  group('Domain events: emission and isolation', () {
    test('create() emits exactly one ContractCreatedEvent', () {
      final c = draft();
      expect(c.domainEvents, hasLength(1));
      expect(c.domainEvents.first, isA<ContractCreatedEvent>());
    });

    test('activate() emits exactly one ContractActivatedEvent', () {
      final activated = persisted().activate(nowUtc: kNow);
      expect(activated.domainEvents, hasLength(1));
      expect(activated.domainEvents.first, isA<ContractActivatedEvent>());
    });

    test('close() emits exactly one ContractClosedEvent', () {
      final closed = persisted(
        status: ContractStatus.active,
      ).close(closedByUserId: 'user-1', reason: 'Encerramento', nowUtc: kNow);
      expect(closed.domainEvents, hasLength(1));
      expect(closed.domainEvents.first, isA<ContractClosedEvent>());
    });

    test(
      'submitForApproval() emits exactly one ContractSubmittedForApprovalEvent',
      () {
        final submitted = persisted().submitForApproval(
          reviewToken: 'tok-review-123',
          nowUtc: kNow,
        );
        expect(submitted.domainEvents, hasLength(1));
        expect(
          submitted.domainEvents.first,
          isA<ContractSubmittedForApprovalEvent>(),
        );
      },
    );

    test(
      'each transition carries only its own event (no event accumulation)',
      () {
        // Activate emits [ContractActivatedEvent].
        // Closing the activated instance should carry only [ContractClosedEvent],
        // not both events — transitions are isolated instances, not chains.
        final activated = persisted().activate(nowUtc: kNow);
        final closed = activated.close(
          closedByUserId: 'user-1',
          reason: 'Encerramento',
          nowUtc: kNow,
        );
        expect(closed.domainEvents, hasLength(1));
        expect(closed.domainEvents.first, isA<ContractClosedEvent>());
      },
    );
  });
}
