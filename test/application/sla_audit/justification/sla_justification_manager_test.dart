import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/sla_justification_manager.dart';
import 'package:veraprob/application/sla_audit/justification/submit_sla_justification_command.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/authorization_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_audit_log.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';

class MockTenantValidator extends Mock implements TenantValidationService {}

class MockSLAJustificationRepo extends Mock
    implements SLAJustificationRepository {}

class MockClock extends Mock implements IDateTimeProvider {}

class FakeSLAJustification extends Fake implements SLAJustification {}

class FakeAuditLog extends Fake implements JustificationAuditLog {}

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
  }

  void setupReviewStubs({
    required DateTime now,
    required SLAJustification pending,
  }) {
    when(() => mockClock.nowUtc()).thenReturn(now);

    when(
      () => mockRepo.findById(
        id: any(named: 'id'),
        organizationId: any(named: 'organizationId'),
      ),
    ).thenAnswer((_) async => pending);

    when(
      () => mockRepo.updateStatus(
        id: any(named: 'id'),
        organizationId: any(named: 'organizationId'),
        status: any(named: 'status'),
        reviewerId: any(named: 'reviewerId'),
        resolutionNotes: any(named: 'resolutionNotes'),
        reviewedAtUtc: any(named: 'reviewedAtUtc'),
      ),
    ).thenAnswer(
      (_) async => pending.copyWith(
        status: JustificationStatus.approved,
        reviewerId: 'gestor-1',
      ),
    );

    when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});
  }

  setUp(() {
    mockTenant = MockTenantValidator();
    mockRepo = MockSLAJustificationRepo();
    mockClock = MockClock();
    rbac = RbacService();

    manager = SLAJustificationManager(
      tenantValidator: mockTenant,
      repository: mockRepo,
      rbac: rbac,
      clock: mockClock,
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

      // ZERO writes: no status update, no audit log
      verifyNever(
        () => mockRepo.updateStatus(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          status: any(named: 'status'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      );
      verifyNever(() => mockRepo.appendAuditLog(any()));

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
        () => mockRepo.updateStatus(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          status: any(named: 'status'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      );
      verifyNever(() => mockRepo.appendAuditLog(any()));
    });

    test(
      'ACCEPTS approve from admin role — audit log seals callerRole "admin"',
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

        final captured = verify(
          () => mockRepo.appendAuditLog(captureAny()),
        ).captured;

        expect(captured, hasLength(1));
        final log = captured.first as JustificationAuditLog;
        expect(log.callerRole, 'admin');
        expect(log.userId, 'admin-user-1');
        expect(log.newStatus, JustificationStatus.approved);
      },
    );

    test(
      'ACCEPTS approve from operator role — audit log seals callerRole "operator"',
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
          () => mockRepo.appendAuditLog(captureAny()),
        ).captured;

        final log = captured.first as JustificationAuditLog;
        expect(log.callerRole, 'operator');
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
      manager = SLAJustificationManager(
        tenantValidator: mockTenant,
        repository: mockRepo,
        rbac: rbac,
        clock: mockClock,
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
        () => mockRepo.findExpiredPending(
          cutoffUtc: any(named: 'cutoffUtc'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => [staleJustification]);

      when(
        () => mockRepo.updateStatus(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          status: any(named: 'status'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
        ),
      ).thenAnswer(
        (_) async =>
            staleJustification.copyWith(status: JustificationStatus.expired),
      );
      when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});

      final count = await manager.expireStaleJustifications(
        organizationId: 'org-1',
      );

      expect(count, 1);

      final statusCapture = verify(
        () => mockRepo.updateStatus(
          id: 'stale-1',
          organizationId: 'org-1',
          status: captureAny(named: 'status'),
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

        manager = SLAJustificationManager(
          tenantValidator: mockTenant,
          repository: mockRepo,
          rbac: rbac,
          clock: mockClock,
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
  // Audit Trail — Status Transitions
  // ═══════════════════════════════════════════════════════════════════════════

  group('Audit Trail — Status Transitions', () {
    test(
      'approve generates audit log with PENDING → APPROVED and callerRole',
      () async {
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

        final captured = verify(
          () => mockRepo.appendAuditLog(captureAny()),
        ).captured;

        expect(captured, hasLength(1));
        final log = captured.first as JustificationAuditLog;
        expect(log.justificationId, 'j-1');
        expect(log.userId, 'gestor-1');
        expect(log.callerRole, 'admin');
        expect(log.previousStatus, JustificationStatus.pending);
        expect(log.newStatus, JustificationStatus.approved);
        expect(log.timestamp, now);
      },
    );

    test(
      'reject generates audit log with PENDING → REJECTED and callerRole',
      () async {
        final now = DateTime.utc(2026, 4, 14, 16, 0);
        final pending = buildPendingJustification(
          id: 'j-2',
          category: SLAJustificationCategory.transitoAtipico,
          description: 'Trânsito test case',
        );

        when(() => mockClock.nowUtc()).thenReturn(now);
        when(
          () => mockRepo.findById(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => pending);
        when(
          () => mockRepo.updateStatus(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            status: any(named: 'status'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
          ),
        ).thenAnswer(
          (_) async => pending.copyWith(
            status: JustificationStatus.rejected,
            reviewerId: 'gestor-1',
          ),
        );
        when(() => mockRepo.appendAuditLog(any())).thenAnswer((_) async {});

        await manager.rejectJustification(
          justificationId: 'j-2',
          organizationId: 'org-1',
          reviewerId: 'gestor-1',
          callerRole: UserRole.operator,
          resolutionNotes: 'Foto não comprova parada forçada',
        );

        final captured = verify(
          () => mockRepo.appendAuditLog(captureAny()),
        ).captured;

        expect(captured, hasLength(1));
        final log = captured.first as JustificationAuditLog;
        expect(log.previousStatus, JustificationStatus.pending);
        expect(log.newStatus, JustificationStatus.rejected);
        expect(log.userId, 'gestor-1');
        expect(log.callerRole, 'operator');
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

    test(
      'approve already-approved justification throws DomainException',
      () async {
        final now = DateTime.utc(2026, 4, 14, 16, 0);
        when(() => mockClock.nowUtc()).thenReturn(now);

        final approved = SLAJustification(
          id: 'j-4',
          organizationId: 'org-1',
          vehicleId: 'vehicle-42',
          eventTimestamp: eventTime,
          category: SLAJustificationCategory.bloqueioPolicial,
          description: 'Bloqueio policial',
          evidenceUrls: ['https://example.com/photo.jpg'],
          evidenceHashes: [validHash],
          status: JustificationStatus.approved,
          createdAt: eventTime.add(const Duration(hours: 1)),
          reviewerId: 'gestor-1',
          resolutionNotes: 'OK',
        );

        when(
          () => mockRepo.findById(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => approved);

        expect(
          () => manager.approveJustification(
            justificationId: 'j-4',
            organizationId: 'org-1',
            reviewerId: 'gestor-2',
            callerRole: UserRole.admin,
            resolutionNotes: null,
          ),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('already APPROVED'),
            ),
          ),
        );
      },
    );
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
}
