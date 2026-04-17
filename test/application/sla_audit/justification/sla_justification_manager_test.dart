// ignore_for_file: deprecated_member_use_from_same_package
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/adaptive_forensic_binary_scanner.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/sla_justification_manager.dart';
import 'package:veraprob/application/sla_audit/justification/submit_sla_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/xss_input_sanitizer.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/authorization_exception.dart';
import 'package:veraprob/domain/sla_audit/concurrency_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_audit_log.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';

// ── Mock classes ─────────────────────────────────────────────────────────────

class MockTenantValidator extends Mock implements TenantValidationService {}

class MockSLAJustificationRepo extends Mock
    implements SLAJustificationRepository {}

class MockClock extends Mock implements IDateTimeProvider {}

class MockEvidenceIntegrityVerifier extends Mock
    implements EvidenceIntegrityVerifier {}

class MockXssInputSanitizer extends Mock implements XssInputSanitizer {}

class MockAdaptiveForensicBinaryScanner extends Mock
    implements AdaptiveForensicBinaryScanner {}

class MockEvidenceLinkChecker extends Mock implements EvidenceLinkChecker {}

class FakeSLAJustification extends Fake implements SLAJustification {}

class FakeAuditLog extends Fake implements JustificationAuditLog {}

// ── Test suite ────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSLAJustification());
    registerFallbackValue(FakeAuditLog());
    registerFallbackValue(JustificationStatus.pending);
    registerFallbackValue(UserRole.admin);
    registerFallbackValue(UserPermission.canReviewJustifications);
  });

  late MockTenantValidator mockTenant;
  late MockSLAJustificationRepo mockRepo;
  late MockClock mockClock;
  late MockEvidenceIntegrityVerifier mockEvidenceVerifier;
  late MockEvidenceLinkChecker mockLinkChecker;
  late RbacService rbac;
  late SLAJustificationManager manager;

  /// SHA-256 of empty string — valid 64-char hex.
  const validHash =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  final eventTime = DateTime.utc(2026, 4, 14, 10, 0);

  SubmitSLAJustificationCommand buildCommand({
    DateTime? eventTimestamp,
    String? category,
    String? description,
    List<String>? evidenceUrls,
    List<String>? evidenceHashes,
  }) {
    return SubmitSLAJustificationCommand(
      organizationId: 'org-1',
      sessionId: 'session-1',
      vehicleId: 'vehicle-42',
      eventTimestamp: eventTimestamp ?? eventTime,
      category: category ?? 'PNEU_FURADO',
      description: description ?? 'Pneu furado na BR-116 km 230',
      evidenceUrls:
          evidenceUrls ?? ['https://storage.supabase.co/evidence/photo1.jpg'],
      evidenceHashes: evidenceHashes ?? [validHash],
      callerUserId: 'driver-1',
    );
  }

  SLAJustification buildPendingJustification({
    String id = 'j-1',
    SLAJustificationCategory category = SLAJustificationCategory.pneuFurado,
    String description = 'Pneu furado test',
  }) {
    return SLAJustification(
      id: id,
      organizationId: 'org-1',
      vehicleId: 'vehicle-42',
      eventTimestamp: eventTime,
      category: category,
      description: description,
      evidenceUrls: ['https://example.com/photo.jpg'],
      evidenceHashes: [validHash],
      status: JustificationStatus.pending,
      createdAt: eventTime.add(const Duration(hours: 1)),
      reviewerId: null,
      resolutionNotes: null,
    );
  }

  /// Stubs for happy-path submit flows.
  ///
  /// Adds stubs for:
  /// - clock → [now]
  /// - tenant validation → no-op
  /// - repo.create → echo entity back
  /// - repo.appendAuditLog → no-op
  /// - repo.findByVehicleAndEvent → null (no existing duplicate)
  /// - evidenceVerifier.verifyAll → [] (all hashes match)
  void setupDefaultStubs({required DateTime now}) {
    when(() => mockClock.nowUtc()).thenReturn(now);
    when(
      () => mockTenant.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockRepo.create(any())).thenAnswer((invocation) async {
      return invocation.positionalArguments[0] as SLAJustification;
    });
    when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});
    when(
      () => mockRepo.findByVehicleAndEvent(
        vehicleId: any(named: 'vehicleId'),
        eventTimestamp: any(named: 'eventTimestamp'),
        organizationId: any(named: 'organizationId'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => mockEvidenceVerifier.verifyAll(
        evidenceUrls: any(named: 'evidenceUrls'),
        declaredHashes: any(named: 'declaredHashes'),
      ),
    ).thenAnswer((_) async => []);
  }

  /// Stubs for review (approve/reject) flows.
  ///
  /// The Manager now uses `updateStatusWithAuditLog` (atomic RPC that handles
  /// status + audit log + deletion queue in a single transaction) followed by
  /// `findById` to reload the fresh entity.
  ///
  /// Red Team v2.1 — ID 2 (Atomicity): `appendAuditLog` is NO LONGER called
  /// separately; it is handled by the RPC.
  void setupReviewStubs({
    required DateTime now,
    required SLAJustification pending,
  }) {
    when(() => mockClock.nowUtc()).thenReturn(now);

    // Pre-load: findById called before updateStatusWithAuditLog to get evidence URLs.
    when(
      () => mockRepo.findById(
        id: any(named: 'id'),
        organizationId: any(named: 'organizationId'),
      ),
    ).thenAnswer((_) async => pending);

    when(
      () => mockRepo.updateStatusWithAuditLog(
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

    // Second findById call AFTER the atomic update to reload the fresh entity.
    // We override to return the approved/rejected entity after the RPC.
    // The first call (pre-load) returns `pending`; the second returns `approved`.
    var findByIdCallCount = 0;
    when(
      () => mockRepo.findById(
        id: any(named: 'id'),
        organizationId: any(named: 'organizationId'),
      ),
    ).thenAnswer((_) async {
      findByIdCallCount++;
      if (findByIdCallCount == 1) return pending;
      return pending.copyWith(
        status: JustificationStatus.approved,
        reviewerId: 'gestor-1',
      );
    });
  }

  setUp(() {
    mockTenant = MockTenantValidator();
    mockRepo = MockSLAJustificationRepo();
    mockClock = MockClock();
    mockEvidenceVerifier = MockEvidenceIntegrityVerifier();
    rbac = RbacService();

    // Create mock instances for new dependencies
    final mockSanitizer = MockXssInputSanitizer();
    final mockFileInspector = MockAdaptiveForensicBinaryScanner();
    mockLinkChecker = MockEvidenceLinkChecker();

    // Configure mocks
    when(() => mockSanitizer.sanitizeText(any())).thenAnswer((inv) {
      final input = inv.positionalArguments[0] as String;
      return input
          .replaceAll(
            RegExp(
              r'<script[^>]*>.*?</script>',
              caseSensitive: false,
              dotAll: true,
            ),
            '',
          )
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
    });

    when(
      () => mockFileInspector.validateEvidence(any()),
    ).thenAnswer((_) async => Future.value());

    when(() => mockLinkChecker.checkLink(any())).thenAnswer(
      (_) async => const EvidenceValidationResult(
        url: '',
        status: EvidenceLinkStatus.available,
      ),
    );

    manager = SLAJustificationManager(
      tenantValidator: mockTenant,
      repository: mockRepo,
      rbac: rbac,
      clock: mockClock,
      evidenceVerifier: mockEvidenceVerifier,
      sanitizer: mockSanitizer,
      fileInspector: mockFileInspector,
      linkChecker: mockLinkChecker,
      eventExistsChecker:
          ({
            required String vehicleId,
            required DateTime eventTimestamp,
            required String organizationId,
          }) async => true,
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Authority Sovereignty — RBAC Guard (Red Team Hotfix)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Authority Sovereignty — RBAC Guard', () {
    test('REJECTS approve from auditor role — throws AuthorizationException, '
        'NO audit log created', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      final pending = buildPendingJustification();
      setupReviewStubs(now: now, pending: pending);

      expect(
        () => manager.approveJustification(
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

      // ZERO writes: RBAC fires before any I/O — no status update, no audit log
      verifyNever(
        () => mockRepo.updateStatusWithAuditLog(
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
        () => mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      );
    });

    test('REJECTS reject from contractorViewer role — '
        'throws AuthorizationException, NO audit log', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      final pending = buildPendingJustification();
      setupReviewStubs(now: now, pending: pending);

      expect(
        () => manager.rejectJustification(
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
        () => mockRepo.updateStatusWithAuditLog(
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
      'ACCEPTS approve from admin role — updateStatusWithAuditLog called with callerRole "admin"',
      () async {
        final now = DateTime.utc(2026, 4, 14, 16, 0);
        final pending = buildPendingJustification();
        setupReviewStubs(now: now, pending: pending);

        await manager.approveJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'admin-user-1',
          callerRole: UserRole.admin,
          resolutionNotes: 'Evidência comprovada',
        );

        // Verify the RPC was called with the correct callerRole
        final captured = verify(
          () => mockRepo.updateStatusWithAuditLog(
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
        setupReviewStubs(now: now, pending: pending);

        await manager.approveJustification(
          justificationId: 'j-1',
          organizationId: 'org-1',
          reviewerId: 'operator-user-1',
          callerRole: UserRole.operator,
          resolutionNotes: null,
        );

        final captured = verify(
          () => mockRepo.updateStatusWithAuditLog(
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

    test(
      'AuthorizationException carries role and requiredPermission metadata',
      () async {
        expect(
          () => manager.approveJustification(
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

  // ═══════════════════════════════════════════════════════════════════════════
  // CX05-INV-22 — Expiration Window
  // ═══════════════════════════════════════════════════════════════════════════

  group('CX05-INV-22 — Expiration Window', () {
    test(
      'REJECTS justification submitted 25 hours after event (> 24h window)',
      () async {
        final now = eventTime.add(const Duration(hours: 25));
        setupDefaultStubs(now: now);

        final command = buildCommand();

        expect(
          () => manager.submitJustification(command),
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

        verifyNever(() => mockRepo.create(any()));
        verifyNever(() => mockRepo.appendAuditLog(any()));
      },
    );

    test(
      'ACCEPTS justification submitted 23 hours after event (< 24h window)',
      () async {
        final now = eventTime.add(const Duration(hours: 23));
        setupDefaultStubs(now: now);

        final command = buildCommand();

        final result = await manager.submitJustification(command);

        expect(result.id, isNotEmpty);
        expect(result.status, JustificationStatus.pending);
        expect(result.vehicleId, 'vehicle-42');
        expect(result.eventTimestamp, eventTime);

        verify(() => mockRepo.create(any())).called(1);
        verify(() => mockRepo.appendAuditLog(any())).called(1);
      },
    );

    test('REJECTS justification at exactly 24h boundary (edge case)', () async {
      final now = eventTime.add(const Duration(hours: 24, seconds: 1));
      setupDefaultStubs(now: now);

      final command = buildCommand();

      expect(
        () => manager.submitJustification(command),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'ACCEPTS justification at exactly 24h (boundary is inclusive)',
      () async {
        final now = eventTime.add(const Duration(hours: 24));
        setupDefaultStubs(now: now);

        final command = buildCommand();

        final result = await manager.submitJustification(command);
        expect(result.status, JustificationStatus.pending);
      },
    );

    test('respects custom expiration window (48h)', () async {
      final mockSanitizer = MockXssInputSanitizer();
      final mockFileInspector = MockAdaptiveForensicBinaryScanner();
      when(
        () => mockSanitizer.sanitizeText(any()),
      ).thenAnswer((inv) => inv.positionalArguments[0] as String);
      when(
        () => mockFileInspector.validateEvidence(any()),
      ).thenAnswer((_) async {});

      manager = SLAJustificationManager(
        tenantValidator: mockTenant,
        repository: mockRepo,
        rbac: rbac,
        clock: mockClock,
        evidenceVerifier: mockEvidenceVerifier,
        sanitizer: mockSanitizer,
        fileInspector: mockFileInspector,
        linkChecker: mockLinkChecker,
        eventExistsChecker:
            ({
              required String vehicleId,
              required DateTime eventTimestamp,
              required String organizationId,
            }) async => true,
        expirationWindow: const Duration(hours: 48),
      );

      final now = eventTime.add(const Duration(hours: 47));
      setupDefaultStubs(now: now);

      final command = buildCommand();

      final result = await manager.submitJustification(command);
      expect(result.status, JustificationStatus.pending);
    });

    test('batch expiration marks PENDING → EXPIRED with audit log', () async {
      final now = DateTime.utc(2026, 4, 16, 12, 0);
      when(() => mockClock.nowUtc()).thenReturn(now);

      final staleJustification = buildPendingJustification(id: 'stale-1');

      when(
        () => mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: any(named: 'afterId'),
        ),
      ).thenAnswer((_) async => [staleJustification]);

      when(
        () => mockRepo.updateStatusAtomic(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      ).thenAnswer((_) async => 1);
      when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});

      final count = await manager.expireStaleJustifications(
        organizationId: 'org-1',
      );

      expect(count, 1);

      final statusCapture = verify(
        () => mockRepo.updateStatusAtomic(
          id: 'stale-1',
          organizationId: 'org-1',
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: captureAny(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      ).captured;
      expect(statusCapture.first, JustificationStatus.expired);

      final auditCapture = verify(
        () => mockRepo.appendAuditLog(captureAny()),
      ).captured;
      final auditLog = auditCapture.first as JustificationAuditLog;
      expect(auditLog.previousStatus, JustificationStatus.pending);
      expect(auditLog.newStatus, JustificationStatus.expired);
      expect(auditLog.userId, 'SYSTEM');
      expect(auditLog.callerRole, 'SYSTEM');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CX05-INV-20 — Linkage Integrity
  // ═══════════════════════════════════════════════════════════════════════════

  group('CX05-INV-20 — Linkage Integrity', () {
    test(
      'REJECTS justification when no matching vehicle event exists',
      () async {
        final now = eventTime.add(const Duration(hours: 2));
        setupDefaultStubs(now: now);

        final mockSanitizer = MockXssInputSanitizer();
        final mockFileInspector = MockAdaptiveForensicBinaryScanner();
        when(
          () => mockSanitizer.sanitizeText(any()),
        ).thenReturn('sanitized_text_valid');
        when(
          () => mockFileInspector.validateEvidence(any()),
        ).thenAnswer((_) async {});

        manager = SLAJustificationManager(
          tenantValidator: mockTenant,
          repository: mockRepo,
          rbac: rbac,
          clock: mockClock,
          evidenceVerifier: mockEvidenceVerifier,
          sanitizer: mockSanitizer,
          fileInspector: mockFileInspector,
          linkChecker: mockLinkChecker,
          eventExistsChecker:
              ({
                required String vehicleId,
                required DateTime eventTimestamp,
                required String organizationId,
              }) async => false,
        );

        final command = buildCommand();

        expect(
          () => manager.submitJustification(command),
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

        verifyNever(() => mockRepo.create(any()));
      },
    );

    test('ACCEPTS justification when matching vehicle event exists', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand();
      final result = await manager.submitJustification(command);

      expect(result.vehicleId, 'vehicle-42');
      expect(result.eventTimestamp, eventTime);
      verify(() => mockRepo.create(any())).called(1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Anti-Double Dipping — Duplicate Vehicle+Event Guard
  // ═══════════════════════════════════════════════════════════════════════════

  group('Anti-Double Dipping', () {
    test('REJECTS duplicate submission when justification already exists for '
        'same vehicle+event anchor', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final existingJustification = buildPendingJustification(id: 'j-existing');

      // Override: findByVehicleAndEvent returns an existing record
      when(
        () => mockRepo.findByVehicleAndEvent(
          vehicleId: any(named: 'vehicleId'),
          eventTimestamp: any(named: 'eventTimestamp'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => existingJustification);

      final command = buildCommand();

      expect(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(contains('already exists'), contains('j-existing')),
          ),
        ),
      );

      // create() must NEVER be called — the duplicate check fires first
      verifyNever(() => mockRepo.create(any()));
      verifyNever(() => mockRepo.appendAuditLog(any()));
    });

    test('ACCEPTS first submission when no duplicate exists '
        '(findByVehicleAndEvent returns null)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now); // stubs findByVehicleAndEvent → null

      final command = buildCommand();
      final result = await manager.submitJustification(command);

      expect(result.status, JustificationStatus.pending);
      verify(() => mockRepo.create(any())).called(1);
    });

    test('REJECTS after duplicate check regardless of event existence — '
        'duplicate check runs after event check', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final existing = buildPendingJustification(id: 'j-dupe');

      when(
        () => mockRepo.findByVehicleAndEvent(
          vehicleId: any(named: 'vehicleId'),
          eventTimestamp: any(named: 'eventTimestamp'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => existing);

      expect(
        () => manager.submitJustification(buildCommand()),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CX05-INV-23 — Evidence Sealing
  // ═══════════════════════════════════════════════════════════════════════════

  group('CX05-INV-23 — Evidence Sealing', () {
    test('REJECTS submission without evidence hashes', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand(evidenceHashes: []);

      expect(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Evidence required'),
          ),
        ),
      );
    });

    test('REJECTS when evidence URL count mismatches hash count', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand(
        evidenceUrls: [
          'https://storage.supabase.co/photo1.jpg',
          'https://storage.supabase.co/photo2.jpg',
        ],
        evidenceHashes: [validHash],
      );

      expect(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('URL count must match hash count'),
              contains('CX05-INV-23'),
            ),
          ),
        ),
      );
    });

    test('REJECTS invalid SHA-256 hash (wrong length)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand(evidenceHashes: ['abc123']);

      expect(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid SHA-256 hash'),
          ),
        ),
      );
    });

    test('REJECTS invalid SHA-256 hash (non-hex characters)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final invalidHash = 'g' * 64;
      final command = buildCommand(evidenceHashes: [invalidHash]);

      expect(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid SHA-256 hash'),
          ),
        ),
      );
    });

    test('ACCEPTS valid SHA-256 hash and preserves in entity', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand();
      final result = await manager.submitJustification(command);

      expect(result.evidenceHashes, [validHash]);
      expect(result.evidenceUrls, hasLength(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Hash Tampering Detection — Server-Side Re-Verification (CX05-INV-23)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Hash Tampering Detection — Server-Side Re-Verification', () {
    test('auto-rejects and throws DomainException when server-side hash diverges '
        '(evidence index 0 mismatch)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      // Override: verifier reports mismatch at index 0
      when(
        () => mockEvidenceVerifier.verifyAll(
          evidenceUrls: any(named: 'evidenceUrls'),
          declaredHashes: any(named: 'declaredHashes'),
        ),
      ).thenAnswer((_) async => [0]);

      when(
        () => mockRepo.updateStatusWithAuditLog(
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
        () => manager.submitJustification(command),
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
        () => mockRepo.updateStatusWithAuditLog(
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

      // appendAuditLog must NOT be called — RPC handles it atomically
      verifyNever(() => mockRepo.appendAuditLog(any()));
    });

    test('auto-rejects when multiple evidence files are tampered '
        '(mismatches at index 0 and 2)', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final twoHashes = [validHash, validHash, validHash];
      final twoUrls = [
        'https://storage.supabase.co/a.jpg',
        'https://storage.supabase.co/b.jpg',
        'https://storage.supabase.co/c.jpg',
      ];

      when(
        () => mockEvidenceVerifier.verifyAll(
          evidenceUrls: any(named: 'evidenceUrls'),
          declaredHashes: any(named: 'declaredHashes'),
        ),
      ).thenAnswer((_) async => [0, 2]);

      when(
        () => mockRepo.updateStatusWithAuditLog(
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
        () => manager.submitJustification(command),
        throwsA(isA<DomainException>()),
      );

      verify(
        () => mockRepo.updateStatusWithAuditLog(
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

    test(
      'ACCEPTS submission when all hashes match (verifyAll returns empty list)',
      () async {
        final now = eventTime.add(const Duration(hours: 2));
        setupDefaultStubs(now: now); // verifyAll → [] by default

        final command = buildCommand();
        final result = await manager.submitJustification(command);

        expect(result.status, JustificationStatus.pending);
        // updateStatusAtomic must NOT be called for non-tampered evidence
        verifyNever(
          () => mockRepo.updateStatusAtomic(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
          ),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Race Condition — Concurrent Modifications (ConcurrencyException)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Race Condition — Concurrent Modifications', () {
    test('approveJustification throws ConcurrencyException when atomic update '
        'returns 0 rows (concurrent modification detected)', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      when(() => mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification();
      // Pre-load findById returns the justification.
      when(
        () => mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => pending);

      when(
        () => mockRepo.updateStatusWithAuditLog(
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
        () => manager.approveJustification(
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
      when(() => mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification();
      when(
        () => mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => pending);

      when(
        () => mockRepo.updateStatusWithAuditLog(
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
        () => manager.rejectJustification(
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
      when(() => mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification();
      var rpcCallCount = 0;

      when(
        () => mockRepo.updateStatusWithAuditLog(
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
        () => mockRepo.findById(
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
      await manager.approveJustification(
        justificationId: 'j-1',
        organizationId: 'org-1',
        reviewerId: 'gestor-1',
        callerRole: UserRole.admin,
        resolutionNotes: null,
      );

      // gestor-2 loses the race
      await expectLater(
        () => manager.approveJustification(
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
        () => mockRepo.updateStatusWithAuditLog(
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
      setupReviewStubs(now: now, pending: pending);

      await manager.approveJustification(
        justificationId: 'j-1',
        organizationId: 'org-1',
        reviewerId: 'gestor-1',
        callerRole: UserRole.admin,
        resolutionNotes: null,
      );

      final captured = verify(
        () => mockRepo.updateStatusWithAuditLog(
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
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // OOM Prevention — Cursor-Based Pagination
  // ═══════════════════════════════════════════════════════════════════════════

  group('OOM Prevention — Cursor-Based Pagination', () {
    test('processes 1000 expired records across two full pages of 500 '
        'and one empty terminator page', () async {
      final now = DateTime.utc(2026, 4, 16, 12, 0);
      when(() => mockClock.nowUtc()).thenReturn(now);

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
        () => mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: null,
        ),
      ).thenAnswer((_) async => page1);

      when(
        () => mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: 'j-500',
        ),
      ).thenAnswer((_) async => page2);

      when(
        () => mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: 'j-1000',
        ),
      ).thenAnswer((_) async => []);

      when(
        () => mockRepo.updateStatusAtomic(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      ).thenAnswer((_) async => 1);
      when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});

      final count = await manager.expireStaleJustifications(
        organizationId: 'org-1',
      );

      expect(count, 1000);

      // Verify cursor advanced to second page
      verify(
        () => mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: 'j-500',
        ),
      ).called(1);

      // Verify cursor advanced to empty terminator
      verify(
        () => mockRepo.findExpiredPendingPaged(
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
      when(() => mockClock.nowUtc()).thenReturn(now);

      // Only 3 stale records — far below page size of 500
      final staleRecords = [
        buildPendingJustification(id: 'stale-1'),
        buildPendingJustification(id: 'stale-2'),
        buildPendingJustification(id: 'stale-3'),
      ];

      when(
        () => mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: any(named: 'afterId'),
        ),
      ).thenAnswer((_) async => staleRecords);

      when(
        () => mockRepo.updateStatusAtomic(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      ).thenAnswer((_) async => 1);
      when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});

      final count = await manager.expireStaleJustifications(
        organizationId: 'org-1',
      );

      expect(count, 3);

      // findExpiredPendingPaged called exactly once — no second page
      verify(
        () => mockRepo.findExpiredPendingPaged(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
          limit: any(named: 'limit'),
          afterId: any(named: 'afterId'),
        ),
      ).called(1);
    });

    test(
      'concurrently-modified records are silently skipped during batch '
      '(updateStatusAtomic returns 0 → no audit log, count not incremented)',
      () async {
        final now = DateTime.utc(2026, 4, 16, 12, 0);
        when(() => mockClock.nowUtc()).thenReturn(now);

        final staleRecords = [
          buildPendingJustification(id: 'stale-1'),
          buildPendingJustification(id: 'stale-2'), // concurrently approved
          buildPendingJustification(id: 'stale-3'),
        ];

        when(
          () => mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).thenAnswer((_) async => staleRecords);

        var atomicCallCount = 0;
        when(
          () => mockRepo.updateStatusAtomic(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
          ),
        ).thenAnswer((_) async {
          atomicCallCount++;
          return atomicCallCount == 2
              ? 0
              : 1; // stale-2 was concurrently modified
        });
        when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});

        final count = await manager.expireStaleJustifications(
          organizationId: 'org-1',
        );

        // stale-2 was skipped — only 2 records actually expired
        expect(count, 2);
        // Audit log written only for the 2 successful expirations
        verify(() => mockRepo.appendAuditLog(any())).called(2);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Cursor Safety — Pagination Cursor Integrity
  // ═══════════════════════════════════════════════════════════════════════════

  group('Cursor Safety — Pagination Cursor Integrity', () {
    test(
      'initial findExpiredPendingPaged call uses afterId: null (no cursor)',
      () async {
        final now = DateTime.utc(2026, 4, 16, 12, 0);
        when(() => mockClock.nowUtc()).thenReturn(now);

        when(
          () => mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).thenAnswer((_) async => []);

        await manager.expireStaleJustifications(organizationId: 'org-1');

        final captured = verify(
          () => mockRepo.findExpiredPendingPaged(
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
      when(() => mockClock.nowUtc()).thenReturn(now);

      final fullPage = List.generate(
        500,
        (i) => buildPendingJustification(id: 'cursor-${i + 1}'),
      );

      var callNumber = 0;
      when(
        () => mockRepo.findExpiredPendingPaged(
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
        () => mockRepo.updateStatusAtomic(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      ).thenAnswer((_) async => 1);
      when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});

      await manager.expireStaleJustifications(organizationId: 'org-1');

      final allAfterIds = verify(
        () => mockRepo.findExpiredPendingPaged(
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
        when(() => mockClock.nowUtc()).thenReturn(now);

        when(
          () => mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).thenAnswer((_) async => []);

        final count = await manager.expireStaleJustifications(
          organizationId: 'org-1',
        );

        expect(count, 0);
        verify(
          () => mockRepo.findExpiredPendingPaged(
            cutoffUtc: any(named: 'cutoffUtc'),
            organizationId: any(named: 'organizationId'),
            limit: any(named: 'limit'),
            afterId: any(named: 'afterId'),
          ),
        ).called(1);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Audit Trail — Status Transitions
  // ═══════════════════════════════════════════════════════════════════════════

  group('Audit Trail — Status Transitions', () {
    test('approve: updateStatusWithAuditLog called with correct parameters '
        '(PENDING → APPROVED, callerRole="admin")', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      final pending = buildPendingJustification();
      setupReviewStubs(now: now, pending: pending);

      await manager.approveJustification(
        justificationId: 'j-1',
        organizationId: 'org-1',
        reviewerId: 'gestor-1',
        callerRole: UserRole.admin,
        resolutionNotes: 'Evidência comprovada',
      );

      // Verify the RPC (which handles audit log internally) was called with
      // the correct status transition and caller attribution.
      verify(
        () => mockRepo.updateStatusWithAuditLog(
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

        when(() => mockClock.nowUtc()).thenReturn(now);

        // Pre-load findById returns the justification.
        var findByIdCallCount = 0;
        when(
          () => mockRepo.findById(
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
          () => mockRepo.updateStatusWithAuditLog(
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

        await manager.rejectJustification(
          justificationId: 'j-2',
          organizationId: 'org-1',
          reviewerId: 'gestor-1',
          callerRole: UserRole.operator,
          resolutionNotes: 'Foto não comprova parada forçada',
        );

        // Verify the RPC (which handles audit log internally) was called with
        // the correct status transition.
        verify(
          () => mockRepo.updateStatusWithAuditLog(
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

    test('reject with short resolution notes throws DomainException', () async {
      expect(
        () => manager.rejectJustification(
          justificationId: 'j-3',
          organizationId: 'org-1',
          reviewerId: 'gestor-1',
          callerRole: UserRole.admin,
          resolutionNotes: 'Short',
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('at least 10 characters'),
          ),
        ),
      );
    });

    test('approve already-modified justification throws ConcurrencyException '
        '(atomic RPC returns 0 rows)', () async {
      final now = DateTime.utc(2026, 4, 14, 16, 0);
      when(() => mockClock.nowUtc()).thenReturn(now);

      final pending = buildPendingJustification(id: 'j-4');
      // Pre-load findById.
      when(
        () => mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => pending);

      // Simulate: the record was already approved by a concurrent operation —
      // WHERE status='PENDING' matches 0 rows.
      when(
        () => mockRepo.updateStatusWithAuditLog(
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
        () => manager.approveJustification(
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

  // ═══════════════════════════════════════════════════════════════════════════
  // Description Validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('Description Validation', () {
    test('REJECTS description shorter than 10 characters', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand(description: 'Too short');

      expect(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('at least 10 characters'),
          ),
        ),
      );
    });

    test('ACCEPTS description with exactly 10 characters', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand(description: 'Exatamente');

      final result = await manager.submitJustification(command);
      expect(result.description, 'Exatamente');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Category Validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('Category Validation', () {
    test('REJECTS invalid category string', () async {
      final now = eventTime.add(const Duration(hours: 2));
      setupDefaultStubs(now: now);

      final command = buildCommand(category: 'INEXISTENTE');

      expect(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid justification category'),
          ),
        ),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Evidence Link Validation — EvidenceValidationService (standalone)
  // ═══════════════════════════════════════════════════════════════════════════

  group('EvidenceValidationService — Evidence Link Validation', () {
    late MockEvidenceLinkChecker mockChecker;
    late EvidenceValidationService validationService;

    setUp(() {
      mockChecker = MockEvidenceLinkChecker();
      validationService = EvidenceValidationService(mockChecker);
    });

    test('returns available status for reachable URL', () async {
      when(() => mockChecker.checkLink(any())).thenAnswer(
        (invocation) async => EvidenceValidationResult(
          url: invocation.positionalArguments[0] as String,
          status: EvidenceLinkStatus.available,
          httpStatusCode: 200,
        ),
      );

      final results = await validationService.validateLinks([
        'https://storage.supabase.co/evidence/photo1.jpg',
      ]);

      expect(results, hasLength(1));
      expect(results.first.status, EvidenceLinkStatus.available);
      expect(results.first.httpStatusCode, 200);
    });

    test('returns missing status for 404 URL', () async {
      when(() => mockChecker.checkLink(any())).thenAnswer(
        (_) async => const EvidenceValidationResult(
          url: 'https://storage.supabase.co/evidence/deleted.jpg',
          status: EvidenceLinkStatus.missing,
          httpStatusCode: 404,
        ),
      );

      final results = await validationService.validateLinks([
        'https://storage.supabase.co/evidence/deleted.jpg',
      ]);

      expect(results.first.status, EvidenceLinkStatus.missing);
    });

    test('returns forbidden status for 403 URL', () async {
      when(() => mockChecker.checkLink(any())).thenAnswer(
        (_) async => const EvidenceValidationResult(
          url: 'https://storage.supabase.co/evidence/restricted.jpg',
          status: EvidenceLinkStatus.forbidden,
          httpStatusCode: 403,
        ),
      );

      final results = await validationService.validateLinks([
        'https://storage.supabase.co/evidence/restricted.jpg',
      ]);

      expect(results.first.status, EvidenceLinkStatus.forbidden);
    });

    test('validates all URLs in parallel and preserves order', () async {
      final urls = [
        'https://storage.supabase.co/evidence/a.jpg',
        'https://storage.supabase.co/evidence/b.jpg',
        'https://storage.supabase.co/evidence/c.jpg',
      ];

      var callIndex = 0;
      final statuses = [
        EvidenceLinkStatus.available,
        EvidenceLinkStatus.missing,
        EvidenceLinkStatus.forbidden,
      ];

      when(() => mockChecker.checkLink(any())).thenAnswer((invocation) async {
        final idx = callIndex++;
        return EvidenceValidationResult(
          url: invocation.positionalArguments[0] as String,
          status: statuses[idx],
        );
      });

      final results = await validationService.validateLinks(urls);

      expect(results, hasLength(3));
      expect(results[0].status, EvidenceLinkStatus.available);
      expect(results[1].status, EvidenceLinkStatus.missing);
      expect(results[2].status, EvidenceLinkStatus.forbidden);
    });

    test('returns empty list for empty URL input', () async {
      final results = await validationService.validateLinks([]);
      expect(results, isEmpty);
      verifyNever(() => mockChecker.checkLink(any()));
    });

    test(
      'returns error status when checker encounters network failure',
      () async {
        when(() => mockChecker.checkLink(any())).thenAnswer(
          (_) async => const EvidenceValidationResult(
            url: 'https://storage.supabase.co/evidence/unreachable.jpg',
            status: EvidenceLinkStatus.error,
            httpStatusCode: null,
          ),
        );

        final results = await validationService.validateLinks([
          'https://storage.supabase.co/evidence/unreachable.jpg',
        ]);

        expect(results.first.status, EvidenceLinkStatus.error);
        expect(results.first.httpStatusCode, isNull);
      },
    );
  });
}
