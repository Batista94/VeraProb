import '_sla_justification_manager_test_helpers.dart';

/// Forensic-governance behavior for [SLAJustificationManager]: authority
/// sovereignty (RBAC rejections), chain-of-custody guards (linkage integrity,
/// anti-double-dipping, server-side hash re-verification), and optimistic-lock
/// concurrency protection. Every test here is a Red Team attack surface.
void main() {
  setUpAll(registerJustificationFallbacks);

  late JustificationTestHarness h;
  setUp(() => h = JustificationTestHarness.create());

  group('Authority Sovereignty — RBAC rejections', () {
    test('REJECTS approve from auditor role — throws AuthorizationException, '
        'NO atomic write created', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      final pending = buildPendingJustification();
      h.setupReviewStubs(now: now, pending: pending);

      expect(
        () => h.manager.approveJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'driver-user-1',
          callerRole: UserRole.auditor,
          resolutionNotes: null,
        ),
        throwsA(
          isA<AuthorizationException>().having(
            (e) => e.role,
            'role',
            'auditor',
          ),
        ),
      );

      // ZERO writes: RBAC fires before any I/O — no atomic RPC called
      verifyNever(
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
      );

      // Also verify NO findById was called — RBAC fires BEFORE any I/O
      verifyNever(
        () => h.mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('REJECTS reject from contractorViewer role — '
        'throws AuthorizationException, NO atomic write', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      final pending = buildPendingJustification();
      h.setupReviewStubs(now: now, pending: pending);

      expect(
        () => h.manager.rejectJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'contractor-user-1',
          callerRole: UserRole.contractorViewer,
          resolutionNotes: 'Tentativa de rejeição sem autoridade',
        ),
        throwsA(
          isA<AuthorizationException>().having(
            (e) => e.role,
            'role',
            'contractorViewer',
          ),
        ),
      );

      verifyNever(
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
      );
    });

    test(
      'AuthorizationException carries role and requiredPermission metadata',
      () async {
        expect(
          () => h.manager.approveJustification(
            justificationId: 'j-1',
            organizationId: 'org-1',
            reviewerId: 'auditor-1',
            callerRole: UserRole.auditor,
            resolutionNotes: null,
          ),
          throwsA(
            isA<AuthorizationException>()
                .having((e) => e.role, 'role', 'auditor')
                .having(
                  (e) => e.requiredPermission,
                  'requiredPermission',
                  'canReviewJustifications',
                ),
          ),
        );
      },
    );
  });

  group('CX05-INV-20 — Linkage Integrity', () {
    test(
      'REJECTS justification when no matching vehicle event exists',
      () async {
        final now = eventTime.add(const Duration(hours: 2));
        h.setupDefaultStubs(now: now);

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
        ).thenReturn('sanitized_text_valid');
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
              }) async => false,
        );

        final command = buildCommand();

        expect(
          () => h.manager.submitJustification(command),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('No matching event found'),
                contains('CX05-INV-20'),
              ),
            ),
          ),
        );

        verifyNever(
          () => h.mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        );
      },
    );
  });

  group('Anti-Double Dipping', () {
    test('REJECTS duplicate submission when justification already exists for '
        'same vehicle+event anchor', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final existingJustification = buildPendingJustification(id: 'j-existing');

      // Override: findByVehicleAndEvent returns an existing record
      when(
        () => h.mockRepo.findByVehicleAndEvent(
          vehicleId: any(named: 'vehicleId'),
          occurrenceTimestamp: any(named: 'occurrenceTimestamp'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => existingJustification);

      final command = buildCommand();

      expect(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(contains('already exists'), contains('j-existing')),
          ),
        ),
      );

      // createWithAuditLog must NEVER be called — the duplicate check fires first
      verifyNever(
        () => h.mockRepo.createWithAuditLog(
          justification: any(named: 'justification'),
          initialAuditLog: any(named: 'initialAuditLog'),
        ),
      );
    });

    test('REJECTS after duplicate check regardless of event existence — '
        'duplicate check runs after event check', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final existing = buildPendingJustification(id: 'j-dupe');

      when(
        () => h.mockRepo.findByVehicleAndEvent(
          vehicleId: any(named: 'vehicleId'),
          occurrenceTimestamp: any(named: 'occurrenceTimestamp'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => existing);

      expect(
        () => h.manager.submitJustification(buildCommand()),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('Hash Tampering Detection — Server-Side Re-Verification', () {
    test('auto-rejects and throws DomainException when server-side hash diverges '
        '(evidence index 0 mismatch)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      // Override: verifier reports mismatch at index 0
      when(
        () => h.mockEvidenceVerifier.verifyAll(
          evidenceUrls: any(named: 'evidenceUrls'),
          declaredHashes: any(named: 'declaredHashes'),
        ),
      ).thenAnswer((_) async => [0]);

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

      final command = buildCommand();

      await expectLater(
        () => h.manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(contains('integrity check failed'), contains('CX05-INV-23')),
          ),
        ),
      );

      // Auto-reject must have been written atomically (RPC) with status = REJECTED
      final captured = verify(
        () => h.mockRepo.updateStatusWithAuditLog(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: captureAny(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: any(named: 'callerRole'),
          evidenceUrls: any(named: 'evidenceUrls'),
        ),
      ).captured;
      expect(captured.first, JustificationStatus.rejected);

      // Separate appendAuditLog must NEVER be called — RPC handles it atomically
      verifyNever(() => h.mockRepo.appendAuditLog(any()));
    });

    test('auto-rejects when multiple evidence files are tampered '
        '(mismatches at index 0 and 2)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final twoHashes = [validHash, validHash, validHash];
      final twoUrls = [
        'https://storage.supabase.co/a.jpg',
        'https://storage.supabase.co/b.jpg',
        'https://storage.supabase.co/c.jpg',
      ];

      when(
        () => h.mockEvidenceVerifier.verifyAll(
          evidenceUrls: any(named: 'evidenceUrls'),
          declaredHashes: any(named: 'declaredHashes'),
        ),
      ).thenAnswer((_) async => [0, 2]);

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

      final command = buildCommand(
        evidenceUrls: twoUrls,
        evidenceHashes: twoHashes,
      );

      await expectLater(
        () => h.manager.submitJustification(command),
        throwsA(isA<DomainException>()),
      );

      verify(
        () => h.mockRepo.updateStatusWithAuditLog(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: JustificationStatus.rejected,
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: any(named: 'callerRole'),
          evidenceUrls: any(named: 'evidenceUrls'),
        ),
      ).called(1);
    });
  });

  group('Race Condition — Concurrent Modifications', () {
    test('approveJustification throws ConcurrencyException when atomic update '
        'returns 0 rows (concurrent modification detected)', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      when(() => h.mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification();
      // Pre-load findById returns the justification.
      when(
        () => h.mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => pending);

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
      ).thenAnswer((_) async => 0); // 0 rows = concurrent modification

      await expectLater(
        () => h.manager.approveJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'gestor-1',
          callerRole: UserRole.admin,
          resolutionNotes: null,
        ),
        throwsA(
          isA<ConcurrencyException>().having(
            (e) => e.message,
            'message',
            contains('concurrent operation'),
          ),
        ),
      );
    });

    test('rejectJustification throws ConcurrencyException when atomic update '
        'returns 0 rows (concurrent modification detected)', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      when(() => h.mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification();
      when(
        () => h.mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => pending);

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
      ).thenAnswer((_) async => 0);

      await expectLater(
        () => h.manager.rejectJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'gestor-1',
          callerRole: UserRole.admin,
          resolutionNotes: 'Foto não comprova parada forçada',
        ),
        throwsA(isA<ConcurrencyException>()),
      );
    });

    test('race condition scenario: second concurrent approve throws '
        'ConcurrencyException (already modified justification)', () async {
      // Simulates: gestor-1 and gestor-2 both read the same PENDING record.
      // gestor-1 approves first (atomic RPC succeeds → 1 row).
      // gestor-2 tries to approve the same record (RPC → 0 rows,
      // because status is now APPROVED, not PENDING).

      final now = DateTime.utc(2026, 4, 14, 16, 0);
      when(() => h.mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification();
      var rpcCallCount = 0;

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
        rpcCallCount++;
        return rpcCallCount == 1 ? 1 : 0; // First wins, second loses
      });

      var findByIdCallCount = 0;
      when(
        () => h.mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {
        findByIdCallCount++;
        // Odd calls = pre-load; even calls = post-update reload
        if (findByIdCallCount % 2 == 1) return pending;
        return pending.copyWith(
          status: JustificationStatus.approved,
          reviewerId: 'gestor-1',
        );
      });

      // gestor-1 wins the race
      await h.manager.approveJustification(
        justificationId: 'j-1',
        organizationId: 'org-1',
        reviewerId: 'gestor-1',
        callerRole: UserRole.admin,
        resolutionNotes: null,
      );

      // gestor-2 loses the race
      await expectLater(
        () => h.manager.approveJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'gestor-2',
          callerRole: UserRole.admin,
          resolutionNotes: null,
        ),
        throwsA(isA<ConcurrencyException>()),
      );

      // RPC was called twice (once per attempt), second returned 0
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
      ).called(2);
    });

    test('approveJustification uses PENDING as expectedCurrentStatus in atomic '
        'RPC — correct optimistic lock predicate', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      final pending = buildPendingJustification();
      h.setupReviewStubs(now: now, pending: pending);

      await h.manager.approveJustification(
        justificationId: 'j-1',
        organizationId: 'org-1',
        reviewerId: 'gestor-1',
        callerRole: UserRole.admin,
        resolutionNotes: null,
      );

      final captured = verify(
        () => h.mockRepo.updateStatusWithAuditLog(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: captureAny(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: any(named: 'callerRole'),
          evidenceUrls: any(named: 'evidenceUrls'),
        ),
      ).captured;

      expect(captured.first, JustificationStatus.pending);
    });

    test('approve already-modified justification throws ConcurrencyException '
        '(atomic RPC returns 0 rows)', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      when(() => h.mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification(id: 'j-4');
      // Pre-load findById.
      when(
        () => h.mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => pending);

      // Simulate: the record was already approved by a concurrent operation —
      // WHERE status='PENDING' matches 0 rows.
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
      ).thenAnswer((_) async => 0);

      await expectLater(
        () => h.manager.approveJustification(
          justificationId: 'j-4',
          organizationId: 'org-1',
          reviewerId: 'gestor-2',
          callerRole: UserRole.admin,
          resolutionNotes: null,
        ),
        throwsA(isA<ConcurrencyException>()),
      );
    });
  });
}
