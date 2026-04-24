/// Forensic Audit Signature: CX-05-v2.2
/// Test Suite: Justification Advanced Hardening — Ironclad Security Tests (v2.2)
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb QA Security Lead
///
/// 5 adversarial test scenarios covering the v2.2 hardening layer:
///   - Fix 3: Null-byte XSS bypass (control-char stripping + UTF-8 round-trip)
///   - Fix 4: Polyglot binary evidence (script payloads past Magic Bytes header)
///   - Fix 5: Evidence Availability Gate (verdict sealed only over live files)
///
/// All tests use the REAL implementation classes (XssInputSanitizer,
/// EvidenceBinaryValidator) to verify end-to-end defence, not mocks.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/sla_justification_manager.dart';
import 'package:veraprob/application/sla_audit/justification/xss_input_sanitizer.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';
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

class MockEvidenceLinkChecker extends Mock implements EvidenceLinkChecker {}

class MockEvidenceStorageReader extends Mock implements EvidenceStorageReader {}

class FakeSLAJustification extends Fake implements SLAJustification {}

class FakeAuditLog extends Fake implements JustificationAuditLog {}

// ── Shared constants ──────────────────────────────────────────────────────────

/// Valid SHA-256 hash (64 hex chars).
const _validHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final _eventTime = DateTime.utc(2026, 4, 16, 2, 0, 0);
final _reviewTime = DateTime.utc(2026, 4, 16, 3, 0, 0);
const _orgId = 'org-ironclad';
const _justificationId = 'just-ironclad-001';

// ── Helper: build a PNG with an embedded PHP payload ─────────────────────────

/// Builds a synthetic file: valid PNG Magic Bytes followed by padding and a
/// PHP payload inserted near the middle of the stream.
///
/// Used by Fix 4 test to exercise the mid-file probe in [_scanForScriptPayloads].
Stream<List<int>> _buildPolyglotPngStream() async* {
  // PNG Magic Bytes header (8 bytes): 89 50 4E 47 0D 0A 1A 0A
  const header = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  yield header;

  // Emit ~512 KB of zero-padding to push the mid-probe past the 512 KB mark.
  // Delivered in 32 KB chunks to mimic realistic streaming from Supabase Storage.
  const chunkSize = 32 * 1024; // 32 KB
  const paddingTotal = 512 * 1024; // 512 KB
  final zeroChunk = List<int>.filled(chunkSize, 0);
  var emitted = 0;
  while (emitted < paddingTotal) {
    yield zeroChunk;
    emitted += chunkSize;
  }

  // Malicious PHP payload with realistic PNG tEXt-chunk prelude so the
  // adjacent ±32B printable-ASCII ratio clears the contextual threshold
  // (Pass 2). Pure zero-padding before <?php would register as binary
  // noise — real polyglots splice payloads into ASCII metadata chunks.
  yield 'tEXtComment: image metadata;\n<?php system(\$_GET["cmd"]); ?>'
      .codeUnits;
}

// ── Main test suite ───────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(FakeSLAJustification());
    registerFallbackValue(JustificationStatus.pending);
    registerFallbackValue(UserRole.admin);
    registerFallbackValue(UserPermission.canReviewJustifications);
  });

  late MockTenantValidator mockTenant;
  late MockSLAJustificationRepo mockRepo;
  late MockClock mockClock;
  late MockEvidenceIntegrityVerifier mockEvidenceVerifier;
  late MockEvidenceLinkChecker mockLinkChecker;

  SLAJustification buildPendingJustification({List<String>? evidenceUrls}) {
    return SLAJustification(
      id: _justificationId,
      organizationId: _orgId,
      vehicleId: 'vehicle-001',
      occurrenceTimestamp: _eventTime,
      category: SLAJustificationCategory.transitoAtipico,
      description: 'Test justification',
      evidenceUrls: evidenceUrls ?? ['https://example.com/evidence.jpg'],
      evidenceHashes: [_validHash],
      status: JustificationStatus.pending,
      createdAt: _eventTime.add(const Duration(minutes: 30)),
      reviewerId: null,
      resolutionNotes: null,
    );
  }

  /// Builds a [SLAJustificationManager] wired with REAL security components
  /// (XssInputSanitizer, ContextualSignatureAnalyzer) and the supplied mocks.
  SLAJustificationManager buildManager({
    required ContextualSignatureAnalyzer fileInspector,
    required XssInputSanitizer sanitizer,
  }) {
    return SLAJustificationManager(
      tenantValidator: mockTenant,
      repository: mockRepo,
      rbac: RbacService(),
      clock: mockClock,
      evidenceVerifier: mockEvidenceVerifier,
      sanitizer: sanitizer,
      fileInspector: fileInspector,
      linkChecker: mockLinkChecker,
      eventExistsChecker:
          ({
            required String vehicleId,
            required DateTime occurrenceTimestamp,
            required String organizationId,
          }) async => true,
    );
  }

  setUp(() {
    mockTenant = MockTenantValidator();
    mockRepo = MockSLAJustificationRepo();
    mockClock = MockClock();
    mockEvidenceVerifier = MockEvidenceIntegrityVerifier();
    mockLinkChecker = MockEvidenceLinkChecker();

    when(() => mockClock.nowUtc()).thenReturn(_reviewTime);

    when(
      () => mockTenant.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});

    // Default: evidence link available (overridden per-test where needed).
    when(() => mockLinkChecker.checkLink(any())).thenAnswer(
      (_) async => const EvidenceValidationResult(
        url: '',
        status: EvidenceLinkStatus.available,
      ),
    );

    when(
      () => mockEvidenceVerifier.verifyAll(
        evidenceUrls: any(named: 'evidenceUrls'),
        declaredHashes: any(named: 'declaredHashes'),
      ),
    ).thenAnswer((_) async => []);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FIX 3 — Null-Byte XSS Bypass Hardening
  //
  // VULNERABILITY: `<scr\x00ipt>` could survive sanitizers that strip control
  // characters AFTER HTML parsing. The null byte reassembled the tag post-parse.
  //
  // REMEDIATION: 3-layer defence in XssInputSanitizer:
  //   Layer 1: Strip null bytes + non-printable control chars.
  //   Layer 2: UTF-8 round-trip normalization.
  //   Layer 3: sanitize_html.
  // ═══════════════════════════════════════════════════════════════════════════

  group('Fix 3 — Null-Byte XSS Bypass', () {
    test('REAL XssInputSanitizer neutralises <scr\\x00ipt> — '
        'output contains no <script tag and no alert payload', () {
      // Arrange: real sanitizer (NOT a mock) to validate the actual defence.
      final sanitizer = XssInputSanitizer();

      // Null byte inside the opening tag — classic bypass vector.
      const maliciousInput = "<scr\x00ipt>alert('xss')</script>";

      // Act
      final result = sanitizer.sanitizeText(maliciousInput);

      // Assert: no executable fragment survives.
      expect(result.toLowerCase(), isNot(contains('<script')));
      expect(result.toLowerCase(), isNot(contains('alert(')));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FIX 4 — Polyglot Binary Evidence (Script Payload Past Magic Bytes)
  //
  // VULNERABILITY: Only the first 512 bytes were inspected. A polyglot file
  // (valid PNG header + PHP payload at byte ~512 KB) would pass MIME detection
  // but execute server-side if the stored file were ever rendered.
  //
  // REMEDIATION: 3-probe streaming strategy (head/mid/tail, 1 MB cap) via
  // EvidenceBinaryValidator._scanForScriptPayloads.
  // ═══════════════════════════════════════════════════════════════════════════

  group('Fix 4 — Polyglot PNG + PHP Mid-File Payload', () {
    test('REAL EvidenceBinaryValidator throws ForensicViolationException '
        'for PNG with <?php payload at ~512 KB offset', () async {
      // Arrange: real validator wired to a streaming storage reader
      // that delivers a polyglot PNG (valid header, PHP body).
      final mockReader = MockEvidenceStorageReader();
      when(
        () => mockReader.streamBytes(url: any(named: 'url')),
      ).thenAnswer((_) => _buildPolyglotPngStream());

      final validator = ContextualSignatureAnalyzer(mockReader);
      const polyglotUrl = 'https://example.com/polyglot.png';

      // Act + Assert
      await expectLater(
        () => validator.validateEvidence([polyglotUrl]),
        throwsA(isA<ForensicViolationException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FIX 5 — Evidence Availability Gate
  //
  // VULNERABILITY: approveJustification / rejectJustification would seal a
  // verdict even when evidence URLs were 404 (files deleted post-submission).
  //
  // REMEDIATION: _assertEvidenceAvailable checks all URLs in parallel before
  // writing the verdict. Throws DomainException with 'Cannot seal verdict'
  // if any URL returns EvidenceLinkStatus.missing.
  // ═══════════════════════════════════════════════════════════════════════════

  group('Fix 5 — Evidence Availability Gate', () {
    test(
      'approveJustification BLOCKED when evidence URL is missing — '
      'throws DomainException, updateStatusWithAuditLog never called',
      () async {
        // Arrange: mock link checker returns "missing" for all URLs.
        when(() => mockLinkChecker.checkLink(any())).thenAnswer(
          (inv) async => EvidenceValidationResult(
            url: inv.positionalArguments[0] as String,
            status: EvidenceLinkStatus.missing,
            httpStatusCode: 404,
          ),
        );

        final pending = buildPendingJustification(
          evidenceUrls: ['https://storage.example.com/deleted-photo.jpg'],
        );

        when(
          () => mockRepo.findById(id: _justificationId, organizationId: _orgId),
        ).thenAnswer((_) async => pending);

        final manager = buildManager(
          sanitizer: XssInputSanitizer(),
          fileInspector: ContextualSignatureAnalyzer(
            MockEvidenceStorageReader(),
          ),
        );

        // Act + Assert: verdict gate throws before writing to DB.
        await expectLater(
          () => manager.approveJustification(
            justificationId: _justificationId,
            organizationId: _orgId,
            reviewerId: 'reviewer-001',
            callerRole: UserRole.admin,
            resolutionNotes: null,
          ),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Cannot seal verdict'),
            ),
          ),
        );

        // updateStatusWithAuditLog MUST NOT have been called.
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
      },
    );

    test(
      'rejectJustification BLOCKED when evidence URL is missing — '
      'throws DomainException, updateStatusWithAuditLog never called',
      () async {
        // Arrange
        when(() => mockLinkChecker.checkLink(any())).thenAnswer(
          (inv) async => EvidenceValidationResult(
            url: inv.positionalArguments[0] as String,
            status: EvidenceLinkStatus.missing,
            httpStatusCode: 404,
          ),
        );

        final pending = buildPendingJustification(
          evidenceUrls: ['https://storage.example.com/deleted-photo.jpg'],
        );

        when(
          () => mockRepo.findById(id: _justificationId, organizationId: _orgId),
        ).thenAnswer((_) async => pending);

        final manager = buildManager(
          sanitizer: XssInputSanitizer(),
          fileInspector: ContextualSignatureAnalyzer(
            MockEvidenceStorageReader(),
          ),
        );

        // Act + Assert
        await expectLater(
          () => manager.rejectJustification(
            justificationId: _justificationId,
            organizationId: _orgId,
            reviewerId: 'reviewer-001',
            callerRole: UserRole.admin,
            resolutionNotes: 'Missing evidence — cannot approve',
          ),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('Cannot seal verdict'),
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
      },
    );

    test('approveJustification PROCEEDS when all evidence available — '
        'updateStatusWithAuditLog called exactly once', () async {
      // Arrange: all links reachable (default stub already set in setUp).
      const evidenceUrl = 'https://storage.example.com/photo.jpg';
      final pending = buildPendingJustification(evidenceUrls: [evidenceUrl]);

      var findByIdCallCount = 0;
      when(
        () => mockRepo.findById(id: _justificationId, organizationId: _orgId),
      ).thenAnswer((_) async {
        findByIdCallCount++;
        if (findByIdCallCount == 1) return pending;
        return pending.copyWith(
          status: JustificationStatus.approved,
          reviewerId: 'reviewer-001',
        );
      });

      when(
        () => mockRepo.updateStatusWithAuditLog(
          id: _justificationId,
          organizationId: _orgId,
          expectedCurrentStatus: JustificationStatus.pending,
          newStatus: JustificationStatus.approved,
          reviewerId: 'reviewer-001',
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: 'admin',
          evidenceUrls: [evidenceUrl],
        ),
      ).thenAnswer((_) async => 1);

      final manager = buildManager(
        sanitizer: XssInputSanitizer(),
        fileInspector: ContextualSignatureAnalyzer(MockEvidenceStorageReader()),
      );

      // Act
      final result = await manager.approveJustification(
        justificationId: _justificationId,
        organizationId: _orgId,
        reviewerId: 'reviewer-001',
        callerRole: UserRole.admin,
        resolutionNotes: null,
      );

      // Assert: verdict sealed, DB written exactly once.
      expect(result.status, JustificationStatus.approved);

      verify(
        () => mockRepo.updateStatusWithAuditLog(
          id: _justificationId,
          organizationId: _orgId,
          expectedCurrentStatus: JustificationStatus.pending,
          newStatus: JustificationStatus.approved,
          reviewerId: 'reviewer-001',
          resolutionNotes: any(named: 'resolutionNotes'),
          reviewedAtUtc: any(named: 'reviewedAtUtc'),
          callerRole: 'admin',
          evidenceUrls: [evidenceUrl],
        ),
      ).called(1);
    });
  });
}
