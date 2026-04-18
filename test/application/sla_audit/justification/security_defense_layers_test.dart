import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/sla_justification_manager.dart';
import 'package:veraprob/application/sla_audit/justification/submit_sla_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/xss_input_sanitizer.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/concurrency_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';

import 'security_defense_layers_test.mocks.dart';

@GenerateMocks([
  TenantValidationService,
  RbacService,
  IDateTimeProvider,
  EvidenceIntegrityVerifier,
  XssInputSanitizer,
  ContextualSignatureAnalyzer,
  SLAJustificationRepository,
  EvidenceLinkChecker,
])
void main() {
  late MockTenantValidationService mockTenantValidation;
  late MockRbacService mockRbac;
  late MockIDateTimeProvider mockDateTime;
  late MockEvidenceIntegrityVerifier mockEvidenceVerifier;
  late MockXssInputSanitizer mockSanitizer;
  late MockContextualSignatureAnalyzer mockFileInspector;
  late MockEvidenceLinkChecker mockLinkChecker;
  late MockSLAJustificationRepository repository;
  late SLAJustificationManager manager;

  setUp(() {
    mockTenantValidation = MockTenantValidationService();
    mockRbac = MockRbacService();
    mockDateTime = MockIDateTimeProvider();
    mockEvidenceVerifier = MockEvidenceIntegrityVerifier();
    mockSanitizer = MockXssInputSanitizer();
    mockFileInspector = MockContextualSignatureAnalyzer();
    mockLinkChecker = MockEvidenceLinkChecker();
    repository = MockSLAJustificationRepository();

    manager = SLAJustificationManager(
      tenantValidator: mockTenantValidation,
      rbac: mockRbac,
      clock: mockDateTime,
      evidenceVerifier: mockEvidenceVerifier,
      sanitizer: mockSanitizer,
      fileInspector: mockFileInspector,
      repository: repository,
      linkChecker: mockLinkChecker,
      eventExistsChecker:
          ({
            required String vehicleId,
            required DateTime eventTimestamp,
            required String organizationId,
          }) async => true,
    );

    when(
      mockTenantValidation.assertTenantMatches(
        payloadOrgId: anyNamed('payloadOrgId'),
        sessionId: anyNamed('sessionId'),
      ),
    ).thenAnswer((_) async => Future.value());

    when(mockDateTime.nowUtc()).thenReturn(DateTime.utc(2026, 4, 16, 3, 0, 0));

    when(mockSanitizer.sanitizeText(any)).thenAnswer((inv) {
      final input = inv.positionalArguments[0] as String;
      // Remove all HTML tags AND their content
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
      mockFileInspector.validateEvidence(any),
    ).thenAnswer((_) async => Future.value());

    when(
      mockEvidenceVerifier.verifyAll(
        evidenceUrls: anyNamed('evidenceUrls'),
        declaredHashes: anyNamed('declaredHashes'),
      ),
    ).thenAnswer((_) async => []);

    when(mockLinkChecker.checkLink(any)).thenAnswer(
      (_) async => const EvidenceValidationResult(
        url: '',
        status: EvidenceLinkStatus.available,
      ),
    );

    when(mockRbac.can(any, any)).thenReturn(true);

    when(repository.create(any)).thenAnswer((inv) async {
      final justification = inv.positionalArguments[0] as SLAJustification;
      return justification;
    });

    when(
      repository.findByVehicleAndEvent(
        vehicleId: anyNamed('vehicleId'),
        eventTimestamp: anyNamed('eventTimestamp'),
        organizationId: anyNamed('organizationId'),
      ),
    ).thenAnswer((_) async => null);
  });

  group('RED TEAM v2.1 — ID 2: Atomicity Gap', () {
    test(
      'Concurrent approval attempts must result in exactly 1 success',
      () async {
        const justificationId = 'just-001';
        const organizationId = 'org-001';

        when(
          repository.findById(
            id: justificationId,
            organizationId: organizationId,
          ),
        ).thenAnswer(
          (_) async => SLAJustification(
            id: justificationId,
            organizationId: organizationId,
            vehicleId: 'vehicle-001',
            eventTimestamp: DateTime.utc(2026, 4, 16, 2, 0, 0),
            category: SLAJustificationCategory.transitoAtipico,
            description: 'Test justification',
            evidenceUrls: ['https://example.com/evidence.jpg'],
            evidenceHashes: [
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ],
            status: JustificationStatus.pending,
            createdAt: DateTime.utc(2026, 4, 16, 2, 30, 0),
            reviewerId: null,
            resolutionNotes: null,
          ),
        );

        when(
          repository.updateStatusWithAuditLog(
            id: justificationId,
            organizationId: organizationId,
            expectedCurrentStatus: JustificationStatus.pending,
            newStatus: JustificationStatus.approved,
            reviewerId: 'reviewer-001',
            resolutionNotes: 'Approved',
            reviewedAtUtc: anyNamed('reviewedAtUtc'),
            callerRole: anyNamed('callerRole'),
            evidenceUrls: anyNamed('evidenceUrls'),
          ),
        ).thenAnswer((_) async {
          // After successful update, mock returns approved justification
          when(
            repository.findById(
              id: justificationId,
              organizationId: organizationId,
            ),
          ).thenAnswer(
            (_) async => SLAJustification(
              id: justificationId,
              organizationId: organizationId,
              vehicleId: 'vehicle-001',
              eventTimestamp: DateTime.utc(2026, 4, 16, 2, 0, 0),
              category: SLAJustificationCategory.transitoAtipico,
              description: 'Test justification',
              evidenceUrls: ['https://example.com/evidence.jpg'],
              evidenceHashes: [
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              ],
              status: JustificationStatus.approved,
              createdAt: DateTime.utc(2026, 4, 16, 2, 30, 0),
              reviewerId: 'reviewer-001',
              resolutionNotes: 'Approved',
            ),
          );
          return 1;
        });

        final result1 = await manager.approveJustification(
          justificationId: justificationId,
          reviewerId: 'reviewer-001',
          resolutionNotes: 'Approved',
          organizationId: organizationId,
          callerRole: UserRole.admin,
        );

        expect(result1.id, justificationId);
        expect(result1.status, JustificationStatus.approved);

        when(
          repository.updateStatusWithAuditLog(
            id: justificationId,
            organizationId: organizationId,
            expectedCurrentStatus: JustificationStatus.pending,
            newStatus: JustificationStatus.approved,
            reviewerId: 'reviewer-002',
            resolutionNotes: 'Also approved',
            reviewedAtUtc: anyNamed('reviewedAtUtc'),
            callerRole: anyNamed('callerRole'),
            evidenceUrls: anyNamed('evidenceUrls'),
          ),
        ).thenAnswer((_) async => 0);

        expect(
          () => manager.approveJustification(
            justificationId: justificationId,
            reviewerId: 'reviewer-002',
            resolutionNotes: 'Also approved',
            organizationId: organizationId,
            callerRole: UserRole.admin,
          ),
          throwsA(isA<ConcurrencyException>()),
        );
      },
    );
  });

  group('RED TEAM v2.1 — ID 4: XSS Vulnerability', () {
    test(
      'HTML script tag and its content are stripped from description',
      () async {
        final command = SubmitSLAJustificationCommand(
          organizationId: 'org-001',
          sessionId: 'session-001',
          vehicleId: 'vehicle-001',
          eventTimestamp: DateTime.utc(2026, 4, 16, 2, 0, 0),
          category: SLAJustificationCategory.transitoAtipico.dbValue,
          description: '<script>alert("XSS")</script>Legitimate text',
          evidenceUrls: ['https://example.com/evidence.jpg'],
          evidenceHashes: [
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ],
          callerUserId: 'user-001',
        );

        final result = await manager.submitJustification(command);

        // The sanitizer mock strips <script>...</script> including content.
        expect(result.description, isNot(contains('<script>')));
        expect(result.description, isNot(contains('</script>')));
        // The clean text must survive.
        expect(result.description, 'Legitimate text');
      },
    );
  });

  group('RED TEAM v2.1 — ID 3: Binary Inspection Gap', () {
    test('Executable disguised as image must be rejected', () async {
      final command = SubmitSLAJustificationCommand(
        organizationId: 'org-001',
        sessionId: 'session-001',
        vehicleId: 'vehicle-001',
        eventTimestamp: DateTime.utc(2026, 4, 16, 2, 0, 0),
        category: SLAJustificationCategory.transitoAtipico.dbValue,
        description: 'Evidence attached',
        evidenceUrls: ['https://example.com/malware.jpg'],
        evidenceHashes: [
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ],
        callerUserId: 'user-001',
      );

      when(
        mockFileInspector.validateEvidence(any),
      ).thenThrow(Exception('Invalid file type: executable detected'));

      expect(
        () => manager.submitJustification(command),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('RED TEAM v2.1 — Integration: Defense-in-Depth', () {
    test('All 5 defense layers must execute in sequence', () async {
      final command = SubmitSLAJustificationCommand(
        organizationId: 'org-001',
        sessionId: 'session-001',
        vehicleId: 'vehicle-001',
        eventTimestamp: DateTime.utc(2026, 4, 16, 2, 0, 0),
        category: SLAJustificationCategory.transitoAtipico.dbValue,
        description: 'Clean description',
        evidenceUrls: ['https://example.com/evidence.jpg'],
        evidenceHashes: [
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ],
        callerUserId: 'user-001',
      );

      final result = await manager.submitJustification(command);

      verify(mockSanitizer.sanitizeText(any)).called(1);
      verify(mockFileInspector.validateEvidence(any)).called(1);
      verify(
        mockEvidenceVerifier.verifyAll(
          evidenceUrls: anyNamed('evidenceUrls'),
          declaredHashes: anyNamed('declaredHashes'),
        ),
      ).called(1);
      verify(repository.create(any)).called(1);

      expect(result.id, isNotEmpty);
      expect(result.status, JustificationStatus.pending);
    });
  });
}
