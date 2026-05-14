// Shared scaffolding for the SLAJustificationManager behavior-domain suites.
//
// The leading underscore is mandatory: it keeps `flutter test` discovery from
// treating this file as an executable suite (which would fail with
// `main() not found`). Test files import only this helper — domain and test
// framework symbols are re-exported below.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/sla_justification_manager.dart';
import 'package:veraprob/application/sla_audit/justification/submit_sla_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/xss_input_sanitizer.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_audit_log.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';

// ── Re-exports — test files import only this helper ──────────────────────────

export 'package:flutter_test/flutter_test.dart';
export 'package:mocktail/mocktail.dart';
export 'package:veraprob/application/shared/tenant_validation_service.dart';
export 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
export 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
export 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';
export 'package:veraprob/application/sla_audit/justification/sla_justification_manager.dart';
export 'package:veraprob/application/sla_audit/justification/submit_sla_justification_command.dart';
export 'package:veraprob/application/sla_audit/justification/xss_input_sanitizer.dart';
export 'package:veraprob/domain/shared/date_time_provider.dart';
export 'package:veraprob/domain/enums/user_permissions.dart';
export 'package:veraprob/domain/enums/user_role.dart';
export 'package:veraprob/domain/services/rbac_service.dart';
export 'package:veraprob/domain/shared/authorization_exception.dart';
export 'package:veraprob/domain/sla_audit/concurrency_exception.dart';
export 'package:veraprob/domain/sla_audit/domain_exception.dart';
export 'package:veraprob/domain/sla_audit/justification/justification_audit_log.dart';
export 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
export 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
export 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
export 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';

// ── Mock classes ─────────────────────────────────────────────────────────────

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

// ── Constants ────────────────────────────────────────────────────────────────

/// SHA-256 of empty string — valid 64-char hex.
const validHash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

final eventTime = DateTime.utc(2026, 4, 14, 10, 0);

/// Registers mocktail fallback values. Call in `setUpAll`.
void registerJustificationFallbacks() {
  registerFallbackValue(FakeSLAJustification());
  registerFallbackValue(FakeAuditLog());
  registerFallbackValue(JustificationStatus.pending);
  registerFallbackValue(UserRole.admin);
  registerFallbackValue(UserPermission.canReviewJustifications);
}

// ── Builders ─────────────────────────────────────────────────────────────────

SubmitSLAJustificationCommand buildCommand({
  DateTime? occurrenceTimestamp,
  String? category,
  String? description,
  List<String>? evidenceUrls,
  List<String>? evidenceHashes,
}) {
  return SubmitSLAJustificationCommand(
    organizationId: 'org-1',
    sessionId: 'session-1',
    vehicleId: 'vehicle-42',
    occurrenceTimestamp: occurrenceTimestamp ?? eventTime,
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
    occurrenceTimestamp: eventTime,
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

// ── Test harness ─────────────────────────────────────────────────────────────

/// Holds all mocks + the wired [SLAJustificationManager] for a single test.
///
/// Create one per test in `setUp` via [JustificationTestHarness.create]. The
/// [manager] field is mutable so JIT-override tests (custom expiration window,
/// non-existent event) can rebuild it with bespoke collaborators.
class JustificationTestHarness {
  JustificationTestHarness._({
    required this.mockTenant,
    required this.mockRepo,
    required this.mockClock,
    required this.mockEvidenceVerifier,
    required this.mockSanitizer,
    required this.mockFileInspector,
    required this.mockLinkChecker,
    required this.rbac,
    required this.manager,
  });

  final MockTenantValidator mockTenant;
  final MockSLAJustificationRepo mockRepo;
  final MockClock mockClock;
  final MockEvidenceIntegrityVerifier mockEvidenceVerifier;
  final MockXssInputSanitizer mockSanitizer;
  final MockContextualSignatureAnalyzer mockFileInspector;
  final MockEvidenceLinkChecker mockLinkChecker;
  final RbacService rbac;
  SLAJustificationManager manager;

  /// Replicates the original global `setUp`: fresh mocks, default sanitizer /
  /// file-inspector / link-checker stubs, and a fully wired manager.
  factory JustificationTestHarness.create() {
    final mockTenant = MockTenantValidator();
    final mockRepo = MockSLAJustificationRepo();
    final mockClock = MockClock();
    final mockEvidenceVerifier = MockEvidenceIntegrityVerifier();
    final rbac = RbacService();
    final mockSanitizer = MockXssInputSanitizer();
    final mockFileInspector = MockContextualSignatureAnalyzer();
    final mockLinkChecker = MockEvidenceLinkChecker();

    when(() => mockSanitizer.sanitize(any())).thenAnswer((inv) {
      final input = inv.positionalArguments[0] as String;
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

    when(
      () => mockFileInspector.validateEvidence(any()),
    ).thenAnswer((_) async => Future.value());

    when(() => mockLinkChecker.checkLink(any())).thenAnswer(
      (_) async => const EvidenceValidationResult(
        url: '',
        status: EvidenceLinkStatus.available,
      ),
    );

    final manager = SLAJustificationManager(
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

    return JustificationTestHarness._(
      mockTenant: mockTenant,
      mockRepo: mockRepo,
      mockClock: mockClock,
      mockEvidenceVerifier: mockEvidenceVerifier,
      mockSanitizer: mockSanitizer,
      mockFileInspector: mockFileInspector,
      mockLinkChecker: mockLinkChecker,
      rbac: rbac,
      manager: manager,
    );
  }

  /// Stubs for happy-path submit flows.
  ///
  /// Configures:
  /// - clock → [now]
  /// - tenant validation → no-op
  /// - repo.createWithAuditLog → echo entity back (atomic creation + audit log)
  /// - repo.findByVehicleAndEvent → null (no existing duplicate)
  /// - evidenceVerifier.verifyAll → [] (all hashes match)
  ///
  /// Red Team ID 2 (Atomicity): Only [createWithAuditLog] is stubbed for write
  /// operations — [appendAuditLog] and [create] are not used.
  void setupDefaultStubs({required DateTime now}) {
    when(() => mockClock.nowUtc()).thenReturn(now);
    when(
      () => mockTenant.assertTenantMatches(
        payloadOrgId: any(named: 'payloadOrgId'),
        sessionId: any(named: 'sessionId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockRepo.createWithAuditLog(
        justification: any(named: 'justification'),
        initialAuditLog: any(named: 'initialAuditLog'),
      ),
    ).thenAnswer((invocation) async {
      return invocation.namedArguments[const Symbol('justification')]
          as SLAJustification;
    });
    when(
      () => mockRepo.findByVehicleAndEvent(
        vehicleId: any(named: 'vehicleId'),
        occurrenceTimestamp: any(named: 'occurrenceTimestamp'),
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
  /// The Manager uses [updateStatusWithAuditLog] (atomic RPC that handles
  /// status + audit log + deletion queue in a single transaction) followed by
  /// [findById] to reload the fresh entity.
  ///
  /// Red Team v2.1 — ID 2 (Atomicity): [appendAuditLog] is NEVER called
  /// separately; it is handled by the RPC.
  void setupReviewStubs({
    required DateTime now,
    required SLAJustification pending,
  }) {
    when(() => mockClock.nowUtc()).thenReturn(now);

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
  }
}
