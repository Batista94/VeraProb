// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_handler.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/pending_fact.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/sync_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/in_memory_justification_repository.dart';

class MockTenantValidator extends Mock implements TenantValidationService {}

class MockLedgerRepo extends Mock implements SlaAuditLedgerRepository {}

class MockFactQueue extends Mock implements LocalFactQueueRepository {}

class MockRbac extends Mock implements RbacService {}

class FakeClock extends Fake implements IDateTimeProvider {
  final DateTime _now;
  FakeClock(this._now);
  @override
  DateTime nowUtc() => _now;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      SlaLedgerEntry(
        organizationId: '',
        type: 'JUSTIFICATION_SUBMITTED',
        contractId: '',
        planVersion: 0,
        occurredAtUtc: DateTime.utc(2026, 4, 14, 18, 0),
      ),
    );
    registerFallbackValue(
      PendingFact.reconstitute(
        factId: '',
        organizationId: '',
        contentHash: '',
        factPayloadJson: '{}',
        receivedAtUtc: DateTime.utc(2026, 4, 14, 18, 0),
        queuedAtUtc: DateTime.utc(2026, 4, 14, 18, 0),
        syncStatus: SyncStatus.pending,
        localSequence: 0,
        retryCount: 0,
      ),
    );
    registerFallbackValue(UserRole.operator);
    registerFallbackValue(UserPermission.canSubmitJustification);
    registerFallbackValue(JustificationStatus.pending);
  });

  group('SubmitJustificationHandler - Edge Cases', () {
    late MockTenantValidator mockTenant;
    late InMemoryJustificationRepository realJustRepo;
    late MockLedgerRepo mockLedger;
    late MockFactQueue mockQueue;
    late MockRbac mockRbac;
    late FakeClock clock;
    late SubmitJustificationHandler handler;

    final kEpoch = DateTime.utc(2026, 4, 14, 18, 0);

    setUp(() {
      mockTenant = MockTenantValidator();
      realJustRepo = InMemoryJustificationRepository();
      mockLedger = MockLedgerRepo();
      mockQueue = MockFactQueue();
      mockRbac = MockRbac();
      clock = FakeClock(kEpoch);

      // INV-1: Secure Baseline. Nada de 'any()'.
      // Qualquer comando fora do padrão 'org-1'/'session-1' vai quebrar os testes.
      when(
        () => mockTenant.assertTenantMatches(
          payloadOrgId: 'org-1',
          sessionId: 'session-1',
        ),
      ).thenAnswer((_) async {});

      when(() => mockLedger.append(any())).thenAnswer((_) async => 'entry-id');
      when(() => mockQueue.enqueue(any())).thenAnswer((_) async {});

      handler = SubmitJustificationHandler(
        tenantValidator: mockTenant,
        justificationRepo: realJustRepo,
        ledger: mockLedger,
        factQueue: mockQueue,
        rbac: mockRbac,
        clock: clock,
      );
    });

    test(
      'EDGE-1: Rejects justification without cryptographic evidence (empty hashes)',
      () async {
        when(
          () => mockRbac.can(
            UserRole.operator,
            UserPermission.canSubmitJustification,
          ),
        ).thenReturn(true);

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'OTHER',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: [],
          sessionId: 'session-1',
          callerUserId: 'user-1',
          callerEmail: 'user@test.com',
          callerRole: UserRole.operator,
          submittedByTokenId: null,
          planVersion: 1,
        );

        await expectLater(
          () => handler.handle(command),
          throwsA(isA<DomainException>()),
        );

        final justifications = await realJustRepo.listByOrg(
          organizationId: 'org-1',
        );
        expect(justifications, isEmpty);
        expect(
          realJustRepo.allEvidences.isEmpty,
          true,
          reason: 'Escudo Binário: Nenhuma evidência deve ser salva em falha',
        );
        verifyNever(() => mockLedger.append(any()));
        verifyNever(() => mockQueue.enqueue(any()));
      },
    );

    test(
      'EDGE-2: Penalty annulment reflects in ledger without erasing original '
      '(INV-3 Append-Only proof)',
      () async {
        when(
          () => mockRbac.can(
            UserRole.operator,
            UserPermission.canSubmitJustification,
          ),
        ).thenReturn(true);

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'OTHER',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: ['hash-1', 'hash-2'],
          sessionId: 'session-1',
          callerUserId: 'user-1',
          callerEmail: 'user@test.com',
          callerRole: UserRole.operator,
          submittedByTokenId: null,
          planVersion: 1,
        );

        final victimJustification = ContractorJustification(
          id: 'victim-just-id',
          organizationId: 'org-1',
          contractId: 'contract-1',
          setId: 'set-1',
          submittedByToken: null,
          category: JustificationCategory.other,
          description: 'Original victim justification',
          status: JustificationStatus.pending,
          reviewedByUserId: null,
          reviewedAtUtc: null,
          createdAtUtc: DateTime.utc(2026, 4, 14, 17, 0),
        );
        await realJustRepo.create(victimJustification);

        await handler.handle(command);

        final justifications = await realJustRepo.listByOrg(
          organizationId: 'org-1',
        );
        expect(justifications.length, 2, reason: 'Prova de cardinalidade n+1');

        final original = justifications.firstWhere(
          (j) => j.id == 'victim-just-id',
        );
        expect(original.description, 'Original victim justification');
        expect(original.createdAtUtc, DateTime.utc(2026, 4, 14, 17, 0));

        final created = justifications.firstWhere(
          (j) => j.id != 'victim-just-id',
        );
        expect(created.organizationId, 'org-1');
        expect(created.contractId, 'contract-1');
        expect(created.setId, 'set-1');
        expect(created.status, JustificationStatus.pending);
        expect(
          created.description,
          'Valid description with at least 20 characters',
        );

        final evidences = await realJustRepo.getEvidence(
          justificationId: created.id,
          organizationId: 'org-1',
        );
        expect(evidences.length, 2, reason: 'Both evidence hashes persisted');
        expect(evidences.map((e) => e.contentHash).toSet(), {
          'hash-1',
          'hash-2',
        });

        final capturedEntry =
            verify(() => mockLedger.append(captureAny())).captured.last
                as SlaLedgerEntry;
        // Validate routing fields on the root of SlaLedgerEntry.
        expect(capturedEntry.organizationId, equals(command.organizationId));
        expect(capturedEntry.contractId, equals(command.contractId));
        expect(capturedEntry.occurredAtUtc.isUtc, isTrue);

        // Validate forensic fields inside the payload map (INV-7).
        final payload = capturedEntry.payload;
        expect(payload['set_id'], equals(command.setId));
        expect(payload['caller_user_id'], equals(command.callerUserId));

        // Binary Shield: validate evidence hashes via listEquals (INV-33).
        final payloadHashes = List<String>.from(
          payload['evidence_hashes'] ?? [],
        );
        expect(listEquals(payloadHashes, command.evidenceHashes), isTrue);
      },
    );

    test(
      'EDGE-3: Idempotency - duplicate submission does not duplicate queue',
      () async {
        when(
          () => mockRbac.can(
            UserRole.operator,
            UserPermission.canSubmitJustification,
          ),
        ).thenReturn(true);

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          contractId: 'contract-1',
          setId: 'set-1',
          category: 'OTHER',
          description: 'Valid description with at least 20 characters',
          evidenceHashes: ['hash-1'],
          sessionId: 'session-1',
          callerUserId: 'user-1',
          callerEmail: 'user@test.com',
          callerRole: UserRole.operator,
          submittedByTokenId: null,
          planVersion: 1,
        );

        await handler.handle(command);
        await handler.handle(command);

        final captured = verify(() => mockQueue.enqueue(captureAny())).captured;
        expect(captured.length, 2);

        expect(captured[0].factId, captured[1].factId);
      },
    );

    test('EDGE-4: Unauthorized role cannot submit justification', () async {
      when(
        () => mockRbac.can(
          UserRole.auditor,
          UserPermission.canSubmitJustification,
        ),
      ).thenReturn(false);

      const command = SubmitJustificationCommand(
        organizationId: 'org-1',
        contractId: 'contract-1',
        setId: 'set-1',
        category: 'OTHER',
        description: 'Valid description with at least 20 characters',
        evidenceHashes: ['hash-1'],
        sessionId: 'session-1',
        callerUserId: 'user-1',
        callerEmail: 'auditor@test.com',
        callerRole: UserRole.auditor,
        submittedByTokenId: null,
        planVersion: 1,
      );

      await expectLater(
        () => handler.handle(command),
        throwsA(isA<DomainException>()),
      );

      final justifications = await realJustRepo.listByOrg(
        organizationId: 'org-1',
      );
      expect(justifications, isEmpty);
      expect(
        realJustRepo.allEvidences.isEmpty,
        true,
        reason: 'Escudo Binário: Nenhuma evidência deve ser salva em falha',
      );
      verifyNever(() => mockLedger.append(any()));
      verifyNever(() => mockQueue.enqueue(any()));
    });

    test('EDGE-5: Token path bypasses RBAC check', () async {
      const command = SubmitJustificationCommand(
        organizationId: 'org-1',
        contractId: 'contract-1',
        setId: 'set-1',
        category: 'OTHER',
        description: 'Valid description with at least 20 characters',
        evidenceHashes: ['hash-1'],
        sessionId: 'session-1',
        callerUserId: null,
        callerEmail: null,
        callerRole: null,
        submittedByTokenId: 'token-123',
        planVersion: 1,
      );

      await handler.handle(command);

      verifyNever(() => mockRbac.can(any(), any()));

      final justifications = await realJustRepo.listByOrg(
        organizationId: 'org-1',
      );
      expect(justifications.length, 1);
    });

    test('EDGE-6: Cross-Tenant Mismatch — sovereignty violation fires, '
        'no repo writes (INV-1, INV-22)', () async {
      when(
        () => mockTenant.assertTenantMatches(
          payloadOrgId: 'org-attacker',
          sessionId: 'session-attacker',
        ),
      ).thenAnswer((_) async {
        throw const SovereigntyViolationException(
          payloadOrgId: 'org-attacker',
          jwtOrgId: 'org-victim',
        );
      });

      const command = SubmitJustificationCommand(
        organizationId: 'org-attacker',
        contractId: 'contract-victim',
        setId: 'set-victim',
        category: 'OTHER',
        description: 'Valid description with at least 20 characters',
        evidenceHashes: ['hash-1'],
        sessionId: 'session-attacker',
        callerUserId: 'attacker-user',
        callerEmail: 'attacker@evil.com',
        callerRole: UserRole.operator,
        submittedByTokenId: null,
        planVersion: 1,
      );

      await expectLater(
        () => handler.handle(command),
        throwsA(isA<SovereigntyViolationException>()),
      );

      verify(
        () => mockTenant.assertTenantMatches(
          payloadOrgId: 'org-attacker',
          sessionId: 'session-attacker',
        ),
      ).called(1);

      final attackerJustifications = await realJustRepo.listByOrg(
        organizationId: 'org-attacker',
      );
      expect(attackerJustifications, isEmpty);

      final victimJustifications = await realJustRepo.listByOrg(
        organizationId: 'org-victim',
      );
      expect(victimJustifications, isEmpty);

      expect(
        realJustRepo.allEvidences.isEmpty,
        true,
        reason: 'Escudo Binário: Nenhuma evidência deve ser salva em falha',
      );
      verifyNever(() => mockLedger.append(any()));
      verifyNever(() => mockQueue.enqueue(any()));
    });
  });
}
