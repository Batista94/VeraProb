import '_sla_justification_manager_test_helpers.dart';

/// Golden-path behavior for [SLAJustificationManager]: authorized reviews,
/// well-formed submissions, and standard status transitions that succeed.
void main() {
  setUpAll(registerJustificationFallbacks);

  late JustificationTestHarness h;
  setUp(() => h = JustificationTestHarness.create());

  group('Authorized review — RBAC accepts', () {
    test(
      'ACCEPTS approve from admin role — updateStatusWithAuditLog called with callerRole "admin"',
      () async {
        final now = DateTime.utc(2026, 4, 14, 16, 0);
        final pending = buildPendingJustification();
        h.setupReviewStubs(now: now, pending: pending);

        await h.manager.approveJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'admin-user-1',
          callerRole: UserRole.admin,
          resolutionNotes: 'Evidência comprovada',
        );

        final captured = verify(
          () => h.mockRepo.updateStatusWithAuditLog(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: captureAny(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).captured;

        expect(captured.first, 'admin');
      },
    );

    test(
      'ACCEPTS approve from operator role — updateStatusWithAuditLog called with callerRole "operator"',
      () async {
        final now = DateTime.utc(2026, 4, 14, 16, 0);
        final pending = buildPendingJustification();
        h.setupReviewStubs(now: now, pending: pending);

        await h.manager.approveJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'operator-user-1',
          callerRole: UserRole.operator,
          resolutionNotes: null,
        );

        final captured = verify(
          () => h.mockRepo.updateStatusWithAuditLog(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: captureAny(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).captured;

        expect(captured.first, 'operator');
      },
    );
  });

  group('Submission — golden path', () {
    test('ACCEPTS justification when matching vehicle event exists', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand();
      final result = await h.manager.submitJustification(command);

      expect(result.vehicleId, 'vehicle-42');
      expect(result.occurrenceTimestamp, eventTime);
      verify(
        () => h.mockRepo.createWithAuditLog(
          justification: any(named: 'justification'),
          initialAuditLog: any(named: 'initialAuditLog'),
        ),
      ).called(1);
    });

    test('ACCEPTS first submission when no duplicate exists '
        '(findByVehicleAndEvent returns null)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now); // stubs findByVehicleAndEvent → null

      final command = buildCommand();
      final result = await h.manager.submitJustification(command);

      expect(result.status, JustificationStatus.pending);
      verify(
        () => h.mockRepo.createWithAuditLog(
          justification: any(named: 'justification'),
          initialAuditLog: any(named: 'initialAuditLog'),
        ),
      ).called(1);
    });

    test('ACCEPTS valid SHA-256 hash and preserves in entity', () async {
      final now = eventTime.add(const Duration(hours: 2));
      h.setupDefaultStubs(now: now);

      final command = buildCommand();
      final result = await h.manager.submitJustification(command);

      expect(result.evidenceHashes, [validHash]);
      expect(result.evidenceUrls, hasLength(1));
    });

    test(
      'ACCEPTS submission when all hashes match (verifyAll returns empty list)',
      () async {
        final now = eventTime.add(const Duration(hours: 2));
        h.setupDefaultStubs(now: now); // verifyAll → [] by default

        final command = buildCommand();
        final result = await h.manager.submitJustification(command);

        expect(result.status, JustificationStatus.pending);

        // updateStatusWithAuditLog must NOT be called for non-tampered evidence
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
      },
    );
  });

  group('Status transitions — standard review', () {
    test('approve: updateStatusWithAuditLog called with correct parameters '
        '(PENDING → APPROVED, callerRole="admin")', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      final pending = buildPendingJustification();
      h.setupReviewStubs(now: now, pending: pending);

      await h.manager.approveJustification(
        justificationId: 'j-1',
        organizationId: 'org-1',
        reviewerId: 'gestor-1',
        callerRole: UserRole.admin,
        resolutionNotes: 'Evidência comprovada',
      );

      // Verify the RPC (which handles audit log internally) was called with
      // the correct status transition and caller attribution.
      verify(
        () => h.mockRepo.updateStatusWithAuditLog(
          id: 'j-1',
          organizationId: 'org-1',
          expectedCurrentStatus: JustificationStatus.pending,
          newStatus: JustificationStatus.approved,
          reviewerId: 'gestor-1',
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: 'admin',
          evidenceUrls: any(named: 'evidenceUrls'),
        ),
      ).called(1);
    });

    test(
      'reject: updateStatusWithAuditLog called with PENDING → REJECTED and callerRole="operator"',
      () async {
        final now = DateTime.utc(2026, 4, 14, 16, 0);
        final pending = buildPendingJustification(
          id: 'j-2',
          category: SLAJustificationCategory.transitoAtipico,
          description: 'Trânsito test case',
        );

        when(() => h.mockClock.nowUtc()).thenReturn(now);

        // Pre-load findById returns the justification.
        var findByIdCallCount = 0;
        when(
          () => h.mockRepo.findById(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async {
          findByIdCallCount++;
          if (findByIdCallCount == 1) return pending;
          return pending.copyWith(
            status: JustificationStatus.rejected,
            reviewerId: 'gestor-1',
          );
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

        await h.manager.rejectJustification(
          justificationId: 'j-2',
          organizationId: 'org-1',
          reviewerId: 'gestor-1',
          callerRole: UserRole.operator,
          resolutionNotes: 'Foto não comprova parada forçada',
        );

        // Verify the RPC (which handles audit log internally) was called with
        // the correct status transition.
        verify(
          () => h.mockRepo.updateStatusWithAuditLog(
            id: 'j-2',
            organizationId: 'org-1',
            expectedCurrentStatus: JustificationStatus.pending,
            newStatus: JustificationStatus.rejected,
            reviewerId: 'gestor-1',
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: 'operator',
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).called(1);
      },
    );
  });
}
