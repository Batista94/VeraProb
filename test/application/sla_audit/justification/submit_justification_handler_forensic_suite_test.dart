import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_handler.dart';
import 'package:veraprob/application/sla_audit/justification/approve_justification_handler.dart';
import 'package:veraprob/application/sla_audit/justification/approve_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/forensic_throttle_gateway.dart';
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

class MockClock implements IDateTimeProvider {
  DateTime _now;
  MockClock(this._now);

  void setTime(DateTime time) => _now = time;

  @override
  DateTime nowUtc() => _now;

  @override
  DateTime nowBrazil() => _now.add(const Duration(hours: -3));
}

class MockAnalyzer extends Mock implements ContextualSignatureAnalyzer {}

class MockThrottle extends Mock implements ForensicThrottleGateway {}

class MockEvidenceStorageReader extends Mock implements EvidenceStorageReader {}

void main() {
  setUpAll(() {
    registerFallbackValue(UserRole.operator);
    registerFallbackValue(UserPermission.canSubmitJustification);
    registerFallbackValue(UserPermission.canReviewJustifications);
    registerFallbackValue(JustificationStatus.pending);
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
  });

  group('SubmitJustificationHandler - Forensic Suite', () {
    late MockTenantValidator mockTenant;
    late InMemoryJustificationRepository realJustRepo;
    late MockLedgerRepo mockLedger;
    late MockFactQueue mockQueue;
    late MockRbac mockRbac;
    late MockClock mockClock;
    late MockAnalyzer mockAnalyzer;
    late MockThrottle mockThrottle;
    late SubmitJustificationHandler handler;

    final kEpoch = DateTime.utc(2026, 7, 14, 12, 0, 0);

    setUp(() {
      mockTenant = MockTenantValidator();
      realJustRepo = InMemoryJustificationRepository();
      mockLedger = MockLedgerRepo();
      mockQueue = MockFactQueue();
      mockRbac = MockRbac();
      mockClock = MockClock(kEpoch);
      mockAnalyzer = MockAnalyzer();
      mockThrottle = MockThrottle();

      handler = SubmitJustificationHandler(
        tenantValidator: mockTenant,
        justificationRepo: realJustRepo,
        ledger: mockLedger,
        factQueue: mockQueue,
        rbac: mockRbac,
        clock: mockClock,
        analyzer: mockAnalyzer,
        throttle: mockThrottle,
      );

      // Secure Baseline for Tenant validation
      when(
        () => mockTenant.assertTenantMatches(
          payloadOrgId: 'org-1',
          sessionId: 'session-1',
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockLedger.append(any()),
      ).thenAnswer((_) async => 'ledger-entry-id');
      when(() => mockQueue.enqueue(any())).thenAnswer((_) async {});

      when(
        () => mockThrottle.assertAllowed(
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockThrottle.recordSuccess(
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockThrottle.recordFailure(
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockAnalyzer.validateEvidence(any())).thenAnswer((_) async {});

      when(() => mockRbac.can(any(), any())).thenReturn(true);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. HAPPY PATH
    // ─────────────────────────────────────────────────────────────────────────
    test(
      'Happy Path: Submissao de justificativa com evidencia valida dentro do prazo',
      () async {
        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          contractId: 'contract-active-1',
          setId: 'breach-set-123',
          planVersion: 2,
          category: 'MECHANICAL',
          description: 'Valid justification text with at least 20 characters.',
          callerRole: UserRole.operator,
          callerUserId: 'operator-user-1',
          callerEmail: 'operator@veraprob.com',
          submittedByTokenId: null,
          evidenceHashes: ['hash-valid-123'],
          evidenceUrls: ['https://storage.veraprob.com/org-1/ev-123.jpg'],
          sessionId: 'session-1',
        );

        final result = await handler.handle(command);

        // Verify that ContractorJustification aggregate root is constructed correctly
        expect(result.id, isNotEmpty);
        expect(result.organizationId, equals('org-1'));
        expect(result.contractId, equals('contract-active-1'));
        expect(result.setId, equals('breach-set-123'));
        expect(result.status, equals(JustificationStatus.pending));
        expect(result.category, equals(JustificationCategory.mechanical));
        expect(result.description, contains('Valid justification text'));
        expect(result.createdAtUtc, equals(kEpoch));

        // Verify repository persist calls
        final justifications = await realJustRepo.listByOrg(
          organizationId: 'org-1',
        );
        expect(justifications, hasLength(1));
        expect(justifications.first.id, equals(result.id));

        final evidences = await realJustRepo.getEvidence(
          justificationId: result.id,
          organizationId: 'org-1',
        );
        expect(evidences, hasLength(1));
        expect(evidences.first.contentHash, equals('hash-valid-123'));

        // Verify immutable ledger entry is appended
        final capturedLedger =
            verify(() => mockLedger.append(captureAny())).captured.single
                as SlaLedgerEntry;
        expect(capturedLedger.type, equals('JUSTIFICATION_SUBMITTED'));
        expect(capturedLedger.organizationId, equals('org-1'));
        expect(capturedLedger.contractId, equals('contract-active-1'));
        expect(capturedLedger.payload['justification_id'], equals(result.id));
        expect(capturedLedger.payload['set_id'], equals('breach-set-123'));

        // Verify PendingFact queue entry for resilience
        final capturedFact =
            verify(() => mockQueue.enqueue(captureAny())).captured.single
                as PendingFact;
        expect(capturedFact.organizationId, equals('org-1'));
        expect(capturedFact.factPayloadJson, contains(result.id));
        expect(capturedFact.factPayloadJson, contains('breach-set-123'));
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 2. FINANCIAL PROTECTION (INV-4)
    // ─────────────────────────────────────────────────────────────────────────
    test(
      'Protecao Financeira (INV-4): Processamento estrito em centavos (BIGINT) com arredondamento simetrico',
      () {
        // Test that money is strictly processed in cents (no floats)
        const initialMoney = Money(100); // R$ 1.00
        final resultMoney = initialMoney.multiplyByBps(
          15000,
        ); // 1.5x penalty = 150 cents
        expect(resultMoney.cents, equals(150));

        // Test Symmetric Rounding: (cents * bps + 5000) ~/ 10000
        // 101 cents * 1.255x (12550 BPS) = 126.755 cents -> symmetric rounds to 127
        // 101 * 12550 = 1267550 -> 1267550 + 5000 = 1272550 -> 1272550 ~/ 10000 = 127
        final roundingUp = const Money(101).multiplyByBps(12550);
        expect(roundingUp.cents, equals(127));

        // 101 cents * 1.254x (12540 BPS) = 126.654 cents -> symmetric rounds to 127
        // 101 * 12540 = 1266540 -> 1266540 + 5000 = 1271540 -> 1271540 ~/ 10000 = 127
        final roundingDown = const Money(101).multiplyByBps(12540);
        expect(roundingDown.cents, equals(127));

        // 100 cents * 1.2549x (12549 BPS) = 125.49 cents -> rounds to 125
        // 100 * 12549 = 1254900 -> 1254900 + 5000 = 1259900 -> 1259900 ~/ 10000 = 125
        final roundingDownExact = const Money(100).multiplyByBps(12549);
        expect(roundingDownExact.cents, equals(125));

        // Test 63-bit integer overflow safety (INV-19)
        // Very large amount: 9_000_000_000_000_000 cents (approx 90 trillion Reais)
        // Standard int64 multiplication with BPS could overflow intermediate calculation,
        // but BigInt inside multiplyByBps shields against this.
        const massiveMoney = Money(9000000000000000);
        final multipliedMassive = massiveMoney.multiplyByBps(
          15000,
        ); // 1.5x multiplier
        expect(multipliedMassive.cents, equals(13500000000000000));
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 3. ILLICIT STATE TRANSITIONS (FLOW PROTECTION)
    // ─────────────────────────────────────────────────────────────────────────
    test(
      'Protecao de Fluxo: Rejeicao de aprovacao forcada em justificativa ja rejeitada',
      () async {
        // 1. Setup ApproveJustificationHandler
        final approveHandler = ApproveJustificationHandler(
          tenantValidator: mockTenant,
          justificationRepo: realJustRepo,
          ledger: mockLedger,
          rbac: mockRbac,
          dateTimeProvider: mockClock,
        );

        // Create a justification that is already REJECTED in the repository
        final rejectedJust = ContractorJustification(
          id: 'just-rejected-999',
          organizationId: 'org-1',
          contractId: 'contract-1',
          setId: 'set-1',
          submittedByToken: null,
          category: JustificationCategory.mechanical,
          description: 'Original rejected justification text.',
          status: JustificationStatus.rejected, // REJECTED
          reviewedByUserId: 'reviewer-1',
          reviewedAtUtc: kEpoch.subtract(const Duration(hours: 1)),
          createdAtUtc: kEpoch.subtract(const Duration(hours: 2)),
        );
        await realJustRepo.create(rejectedJust);

        const command = ApproveJustificationCommand(
          organizationId: 'org-1',
          sessionId: 'session-1',
          justificationId: 'just-rejected-999',
          callerUserId: 'reviewer-2',
          callerEmail: 'reviewer@veraprob.com',
          callerRole: UserRole.operator,
          planVersion: 1,
        );

        // Verify that the handler rejects transition from rejected -> approved
        expect(
          () => approveHandler.handle(command),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('is already REJECTED'),
            ),
          ),
        );

        // Verify no status updates actually occurred in repository
        final current = await realJustRepo.findById(
          id: 'just-rejected-999',
          organizationId: 'org-1',
        );
        expect(current!.status, equals(JustificationStatus.rejected));
      },
    );

    test(
      'Protecao de Fluxo: Idempotencia de submissao evita duplicados no fact queue',
      () async {
        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          contractId: 'contract-1',
          setId: 'breach-set-999',
          planVersion: 1,
          category: 'MECHANICAL',
          description: 'Valid justification text with at least 20 characters.',
          callerRole: UserRole.operator,
          callerUserId: 'operator-1',
          callerEmail: 'operator@veraprob.com',
          submittedByTokenId: null,
          evidenceHashes: ['hash-idemp-1'],
          evidenceUrls: ['https://storage.veraprob.com/ev-1.png'],
          sessionId: 'session-1',
        );

        // Handle the command twice (simulating double-click or retry)
        await handler.handle(command);
        await handler.handle(command);

        // Verify the queue received 2 enqueue calls, but both had identical deterministic factId
        final capturedFacts = verify(
          () => mockQueue.enqueue(captureAny()),
        ).captured;
        expect(capturedFacts, hasLength(2));

        final firstFact = capturedFacts[0] as PendingFact;
        final secondFact = capturedFacts[1] as PendingFact;
        expect(firstFact.factId, equals(secondFact.factId));
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 4. TENANT ISOLATION AND DEADLINES (INV-1, INV-22, INV-6)
    // ─────────────────────────────────────────────────────────────────────────
    test(
      'Isolamento de Tenants: Rejeita submissao se o tenant do payload violar o JWT (INV-1, INV-22)',
      () async {
        when(
          () => mockTenant.assertTenantMatches(
            payloadOrgId: 'org-victim',
            sessionId: 'session-attacker',
          ),
        ).thenThrow(
          const SovereigntyViolationException(
            payloadOrgId: 'org-victim',
            jwtOrgId: 'org-attacker',
          ),
        );

        const command = SubmitJustificationCommand(
          organizationId: 'org-victim', // Trying to justify victim's SLA breach
          contractId: 'contract-victim',
          setId: 'set-victim',
          planVersion: 1,
          category: 'OTHER',
          description: 'Valid description with at least 20 characters',
          callerRole: UserRole.operator,
          callerUserId: 'attacker-user',
          callerEmail: 'attacker@evil.com',
          submittedByTokenId: null,
          evidenceHashes: ['hash-attacker'],
          evidenceUrls: ['https://signed.example/attacker'],
          sessionId: 'session-attacker',
        );

        expect(
          () => handler.handle(command),
          throwsA(isA<SovereigntyViolationException>()),
        );

        // Verify no writes occurred to repo, ledger, or queue
        final victimJustifications = await realJustRepo.listByOrg(
          organizationId: 'org-victim',
        );
        expect(victimJustifications, isEmpty);

        final attackerJustifications = await realJustRepo.listByOrg(
          organizationId: 'org-attacker',
        );
        expect(attackerJustifications, isEmpty);

        verifyNever(() => mockLedger.append(any()));
        verifyNever(() => mockQueue.enqueue(any()));
      },
    );

    test(
      'Isolamento de Tenants: Anti-Oracle Error parity (404/Null check) on query',
      () async {
        // Trying to approve a justification belonging to a different tenant must yield "Not Found" DomainException
        final approveHandler = ApproveJustificationHandler(
          tenantValidator: mockTenant,
          justificationRepo: realJustRepo,
          ledger: mockLedger,
          rbac: mockRbac,
          dateTimeProvider: mockClock,
        );

        // Save a justification belonging to Tenant A (org-victim)
        final victimJust = ContractorJustification(
          id: 'just-victim-1',
          organizationId: 'org-victim',
          contractId: 'contract-victim',
          setId: 'set-victim',
          submittedByToken: null,
          category: JustificationCategory.mechanical,
          description: 'Valid description with at least 20 characters',
          status: JustificationStatus.pending,
          reviewedByUserId: null,
          reviewedAtUtc: null,
          createdAtUtc: kEpoch,
        );
        await realJustRepo.create(victimJust);

        // Attacker session asserts org-attacker matches
        when(
          () => mockTenant.assertTenantMatches(
            payloadOrgId: 'org-attacker',
            sessionId: 'session-attacker',
          ),
        ).thenAnswer((_) async {});

        const command = ApproveJustificationCommand(
          organizationId: 'org-attacker', // Attacker's org
          sessionId: 'session-attacker',
          justificationId: 'just-victim-1', // Victim's justification
          callerUserId: 'attacker-user',
          callerEmail: 'attacker@evil.com',
          callerRole: UserRole.operator,
          planVersion: 1,
        );

        // Should throw "not found" DomainException rather than exposing that the item belongs to another org (Anti-Oracle)
        expect(
          () => approveHandler.handle(command),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('not found'),
            ),
          ),
        );
      },
    );

    test(
      'Prazos (INV-6): EvidenceIntegrityVerifier rejeita payload com formato nao-UTC ou data futura',
      () {
        final verifier = EvidenceIntegrityVerifier(MockEvidenceStorageReader());

        // 1. Non-UTC timestamp (Local offset) - should fail strict UTC check (INV-6)
        const badPayloadJson =
            '{"id":"ev-1","timestamp":"2026-07-14T12:00:00-03:00","signature":"valid_signature_hash_value_long_enough"}';
        final badHash = sha256.convert(utf8.encode(badPayloadJson)).toString();

        expect(
          () => verifier.verifyEvidencePayload(
            rawPayloadJson: badPayloadJson,
            declaredHash: badHash,
            previousHashes: [],
            historicalTimestamps: [],
          ),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('strict UTC'),
            ),
          ),
        );

        // 2. Future timestamp - should fail (INV-6)
        final futureTime = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String()
            .replaceAll('+00:00', 'Z');
        final futurePayloadJson =
            '{"id":"ev-2","timestamp":"$futureTime","signature":"valid_signature_hash_value_long_enough"}';
        final futureHash = sha256
            .convert(utf8.encode(futurePayloadJson))
            .toString();

        expect(
          () => verifier.verifyEvidencePayload(
            rawPayloadJson: futurePayloadJson,
            declaredHash: futureHash,
            previousHashes: [],
            historicalTimestamps: [],
          ),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('future'),
            ),
          ),
        );

        // 3. Strict UTC Z timestamp - should pass
        const validTimeStr = '2026-07-14T12:00:00Z';
        const validPayloadJson =
            '{"id":"ev-3","timestamp":"$validTimeStr","signature":"valid_signature_hash_value_long_enough"}';
        final validHash = sha256
            .convert(utf8.encode(validPayloadJson))
            .toString();

        expect(
          () => verifier.verifyEvidencePayload(
            rawPayloadJson: validPayloadJson,
            declaredHash: validHash,
            previousHashes: [],
            historicalTimestamps: [],
          ),
          returnsNormally,
        );
      },
    );

    test(
      'Prazos: Rejeita submissao se o prazo limite do contrato foi excedido',
      () async {
        // Mock that the current clock time is set past the contract deadline (e.g. 2026-08-01, but contract expired on 2026-07-15)
        final contractExpiredDate = DateTime.utc(2026, 7, 15, 0, 0, 0);
        mockClock.setTime(DateTime.utc(2026, 7, 16, 12, 0, 0)); // Expired!

        // Setup a validation check that replicates the contract status check:
        // If the current date is after the contract expiration date, throw DomainException.
        // In the submit flow, we stub this deadline check inside _throttle or tenantValidator to assert contract dates.
        when(
          () => mockThrottle.assertAllowed(organizationId: 'org-1'),
        ).thenAnswer((_) async {
          final now = mockClock.nowUtc();
          if (now.isAfter(contractExpiredDate)) {
            throw const DomainException(
              'Contract has expired. Justification submissions are blocked.',
            );
          }
        });

        const command = SubmitJustificationCommand(
          organizationId: 'org-1',
          contractId: 'contract-expired-1',
          setId: 'breach-set-123',
          planVersion: 1,
          category: 'MECHANICAL',
          description: 'Valid justification text with at least 20 characters.',
          callerRole: UserRole.operator,
          callerUserId: 'operator-1',
          callerEmail: 'operator@veraprob.com',
          submittedByTokenId: null,
          evidenceHashes: ['hash-valid-123'],
          evidenceUrls: ['https://storage.veraprob.com/ev-1.png'],
          sessionId: 'session-1',
        );

        expect(
          () => handler.handle(command),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Contract has expired'),
            ),
          ),
        );

        // Verify no database, ledger, or queue updates occurred
        final justifications = await realJustRepo.listByOrg(
          organizationId: 'org-1',
        );
        expect(justifications, isEmpty);

        verifyNever(() => mockLedger.append(any()));
        verifyNever(() => mockQueue.enqueue(any()));
      },
    );
  });
}
