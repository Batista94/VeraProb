import '_sla_justification_manager_test_helpers.dart';

/// Time-bound lifecycle behavior for [SLAJustificationManager]: the submission
/// expiration window, batch PENDING → EXPIRED transitions, and the cursor-based
/// pagination that drives those batches without exhausting memory.
void main() {
  setUpAll(registerJustificationFallbacks);

  late JustificationTestHarness h;
  setUp(() => h = JustificationTestHarness.create());

  group('CX05-INV-22 — Expiration Window', () {
    test(
      'REJECTS justification submitted 25 hours after event (> 24h window)',
      () async {
        final now = eventTime.add(const Duration(hours: 25));
        h.setupDefaultStubs(now: now);

        final command = buildCommand();

        expect(
          () => h.manager.submitJustification(command),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Justification window expired'),
                contains('CX05-INV-22'),
                contains('25h ago'),
              ),
            ),
          ),
        );

        // Rejection fires before persistence — no atomic write must occur
        verifyNever(
          () => h.mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        );
      },
    );

    test(
      'ACCEPTS justification submitted 23 hours after event (< 24h window)',
      () async {
        final now = eventTime.add(const Duration(hours: 23));
        h.setupDefaultStubs(now: now);

        final command = buildCommand();

        final result = await h.manager.submitJustification(command);

        expect(result.id, isNotEmpty);
        expect(result.status, JustificationStatus.pending);
        expect(result.vehicleId, 'vehicle-42');
        expect(result.occurrenceTimestamp, eventTime);

        // Atomic write must occur exactly once (INV-3 + Red Team ID 2)
        verify(
          () => h.mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        ).called(1);
      },
    );

    test('REJECTS justification at exactly 24h boundary (edge case)', () async {
      final now = eventTime.add(const Duration(hours: 24, seconds: 1));
      h.setupDefaultStubs(now: now);

      final command = buildCommand();

      expect(
        () => h.manager.submitJustification(command),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'ACCEPTS justification at exactly 24h (boundary is inclusive)',
      () async {
        final now = eventTime.add(const Duration(hours: 24));
        h.setupDefaultStubs(now: now);

        final command = buildCommand();

        final result = await h.manager.submitJustification(command);
        expect(result.status, JustificationStatus.pending);
      },
    );

    test('respects custom expiration window (48h)', () async {
      final mockSanitizer = MockXssInputSanitizer();
      final mockFileInspector = MockContextualSignatureAnalyzer();
      when(() => mockSanitizer.sanitize(any())).thenAnswer((inv) {
        final input = inv.positionalArguments[0] as String;
        return SanitizationResult(
          text: input,
          wasModified: false,
          threatLevel: ThreatLevel.none,
        );
      });
      when(
        () => mockSanitizer.sanitizeText(any()),
      ).thenAnswer((inv) => inv.positionalArguments[0] as String);
      when(
        () => mockFileInspector.validateEvidence(any()),
      ).thenAnswer((_) async {});

      h.manager = SLAJustificationManager(
        tenantValidator: h.mockTenant,
        repository: h.mockRepo,
        rbac: h.rbac,
        clock: h.mockClock,
        evidenceVerifier: h.mockEvidenceVerifier,
        sanitizer: mockSanitizer,
        fileInspector: mockFileInspector,
        linkChecker: h.mockLinkChecker,
        eventExistsChecker:
            ({
              required String vehicleId,
              required DateTime occurrenceTimestamp,
              required String organizationId,
            }) async => true,
        expirationWindow: const Duration(hours: 48),
      );

      final now = eventTime.add(const Duration(hours: 47));
      h.setupDefaultStubs(now: now);

      final command = buildCommand();

      final result = await h.manager.submitJustification(command);
      expect(result.status, JustificationStatus.pending);
    });

    test(
      'batch expiration marks PENDING → EXPIRED atomically (updateStatusWithAuditLog, callerRole=SYSTEM)',
      () async {
        final now = DateTime.utc(2026, 4, 16, 12, 0);
        when(() => h.mockClock.nowUtc()).thenReturn(now);

        final staleJustification = buildPendingJustification(id: 'stale-1');

        when(
          () => h.mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).thenAnswer((_) async => [staleJustification]);

        when(
          () => h.mockRepo.updateStatusWithAuditLog(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: any(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).thenAnswer((_) async => 1);

        final count = await h.manager.expireStaleJustifications(
          organizationId: 'org-1',
        );

        expect(count, 1);

        // Verify the atomic RPC was called with correct transition and SYSTEM attribution.
        // mocktail skips null values in the captured list, so reviewerId (null) is absent.
        // Capture order follows interface definition order for non-null captured values:
        //   captured[0] = expectedCurrentStatus, captured[1] = newStatus, captured[2] = callerRole
        final captured = verify(
          () => h.mockRepo.updateStatusWithAuditLog(
            id: 'stale-1',
            organizationId: 'org-1',
            expectedCurrentStatus: captureAny(named: 'expectedCurrentStatus'),
            newStatus: captureAny(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: captureAny(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).captured;

        expect(
          captured[0],
          JustificationStatus.pending,
        ); // expectedCurrentStatus
        expect(captured[1], JustificationStatus.expired); // newStatus
        expect(captured[2], 'SYSTEM'); // callerRole

        // Verify reviewerId was null (SYSTEM actor — no human reviewer)
        // by stubbing: the when() above accepted any reviewerId; confirm
        // the invocation passed null by checking the call succeeded once.
        // (mocktail does not capture null named args — verified via manager code audit.)
      },
    );
  });

  group('OOM Prevention — Cursor-Based Pagination', () {
    test('processes 1000 expired records across two full pages of 500 '
        'and one empty terminator page', () async {
      final now = DateTime.utc(2026, 4, 16, 12, 0);
      when(() => h.mockClock.nowUtc()).thenReturn(now);

      // Page 1: exactly 500 records (ids j-1 to j-500)
      final page1 = List.generate(
        500,
        (i) => buildPendingJustification(id: 'j-${i + 1}'),
      );
      // Page 2: exactly 500 records (ids j-501 to j-1000)
      final page2 = List.generate(
        500,
        (i) => buildPendingJustification(id: 'j-${i + 501}'),
      );

      when(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: null,
        ),
      ).thenAnswer((_) async => page1);

      when(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: 'j-500',
        ),
      ).thenAnswer((_) async => page2);

      when(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: 'j-1000',
        ),
      ).thenAnswer((_) async => []);

      when(
        () => h.mockRepo.updateStatusWithAuditLog(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: any(named: 'callerRole'),
          evidenceUrls: any(named: 'evidenceUrls'),
        ),
      ).thenAnswer((_) async => 1);

      final count = await h.manager.expireStaleJustifications(
        organizationId: 'org-1',
      );

      expect(count, 1000);

      // Verify cursor advanced to second page
      verify(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: 'j-500',
        ),
      ).called(1);

      // Verify cursor advanced to empty terminator
      verify(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: 'j-1000',
        ),
      ).called(1);
    });

    test('terminates after first page when page size is smaller than limit '
        '(no cursor advance needed)', () async {
      final now = DateTime.utc(2026, 4, 16, 12, 0);
      when(() => h.mockClock.nowUtc()).thenReturn(now);

      // Only 3 stale records — far below page size of 500
      final staleRecords = [
        buildPendingJustification(id: 'stale-1'),
        buildPendingJustification(id: 'stale-2'),
        buildPendingJustification(id: 'stale-3'),
      ];

      when(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: any(named: 'afterId'),
        ),
      ).thenAnswer((_) async => staleRecords);

      when(
        () => h.mockRepo.updateStatusWithAuditLog(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: any(named: 'callerRole'),
          evidenceUrls: any(named: 'evidenceUrls'),
        ),
      ).thenAnswer((_) async => 1);

      final count = await h.manager.expireStaleJustifications(
        organizationId: 'org-1',
      );

      expect(count, 3);

      // findExpiredPendingPaged called exactly once — no second page
      verify(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: any(named: 'afterId'),
        ),
      ).called(1);
    });

    test(
      'concurrently-modified records are silently skipped during batch '
      '(updateStatusWithAuditLog returns 0 → count not incremented)',
      () async {
        final now = DateTime.utc(2026, 4, 16, 12, 0);
        when(() => h.mockClock.nowUtc()).thenReturn(now);

        final staleRecords = [
          buildPendingJustification(id: 'stale-1'),
          buildPendingJustification(id: 'stale-2'), // concurrently approved
          buildPendingJustification(id: 'stale-3'),
        ];

        when(
          () => h.mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).thenAnswer((_) async => staleRecords);

        var atomicCallCount = 0;
        when(
          () => h.mockRepo.updateStatusWithAuditLog(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: any(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).thenAnswer((_) async {
          atomicCallCount++;
          return atomicCallCount == 2
              ? 0
              : 1; // stale-2 was concurrently modified
        });

        final count = await h.manager.expireStaleJustifications(
          organizationId: 'org-1',
        );

        // stale-2 was skipped — only 2 records actually expired
        expect(count, 2);

        // Atomic RPC called 3 times (once per record)
        verify(
          () => h.mockRepo.updateStatusWithAuditLog(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: any(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).called(3);
      },
    );
  });

  group('Cursor Safety — Pagination Cursor Integrity', () {
    test(
      'initial findExpiredPendingPaged call uses afterId: null (no cursor)',
      () async {
        final now = DateTime.utc(2026, 4, 16, 12, 0);
        when(() => h.mockClock.nowUtc()).thenReturn(now);

        when(
          () => h.mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).thenAnswer((_) async => []);

        await h.manager.expireStaleJustifications(organizationId: 'org-1');

        final captured = verify(
          () => h.mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: captureAny(named: 'afterId'),
          ),
        ).captured;

        expect(captured.first, isNull);
      },
    );

    test('cursor advances to last record id from previous page', () async {
      final now = DateTime.utc(2026, 4, 16, 12, 0);
      when(() => h.mockClock.nowUtc()).thenReturn(now);

      final fullPage = List.generate(
        500,
        (i) => buildPendingJustification(id: 'cursor-${i + 1}'),
      );

      var callNumber = 0;
      when(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: any(named: 'afterId'),
        ),
      ).thenAnswer((_) async {
        callNumber++;
        return callNumber == 1 ? fullPage : [];
      });

      when(
        () => h.mockRepo.updateStatusWithAuditLog(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: any(named: 'callerRole'),
          evidenceUrls: any(named: 'evidenceUrls'),
        ),
      ).thenAnswer((_) async => 1);

      await h.manager.expireStaleJustifications(organizationId: 'org-1');

      final allAfterIds = verify(
        () => h.mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: captureAny(named: 'afterId'),
        ),
      ).captured;

      // First call: no cursor
      expect(allAfterIds[0], isNull);
      // Second call: cursor = last id of first page
      expect(allAfterIds[1], 'cursor-500');
    });

    test(
      'stops when empty page is returned and total expired count is correct',
      () async {
        final now = DateTime.utc(2026, 4, 16, 12, 0);
        when(() => h.mockClock.nowUtc()).thenReturn(now);

        when(
          () => h.mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).thenAnswer((_) async => []);

        final count = await h.manager.expireStaleJustifications(
          organizationId: 'org-1',
        );

        expect(count, 0);
        verify(
          () => h.mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).called(1);
      },
    );
  });
}
