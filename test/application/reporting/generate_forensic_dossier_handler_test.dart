import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/reporting/generate_forensic_dossier_handler.dart';
import 'package:veraprob/domain/reporting/forensic_dossier.dart';
import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';
import 'package:veraprob/domain/reporting/i_static_map_service.dart';
import 'package:veraprob/domain/reporting/i_pdf_dossier_log_repository.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';

class MockStaticMapService extends Mock implements IStaticMapService {}

class MockForensicPdfGenerator extends Mock implements IForensicPdfGenerator {}

class MockPdfDossierLogRepository extends Mock
    implements IPdfDossierLogRepository {}

class MockTenantValidationService extends Mock
    implements TenantValidationService {}

void main() {
  group('GenerateForensicDossierHandler', () {
    late MockStaticMapService mockMapService;
    late MockForensicPdfGenerator mockPdfGenerator;
    late MockPdfDossierLogRepository mockLogRepo;
    late MockTenantValidationService mockTenantValidator;
    late GenerateForensicDossierHandler handler;
    late SlaLedgerEntry baseEntry;

    setUp(() {
      mockMapService = MockStaticMapService();
      mockPdfGenerator = MockForensicPdfGenerator();
      mockLogRepo = MockPdfDossierLogRepository();
      mockTenantValidator = MockTenantValidationService();

      handler = GenerateForensicDossierHandler(
        mockMapService,
        mockPdfGenerator,
        mockLogRepo,
        mockTenantValidator,
      );

      baseEntry = SlaLedgerEntry(
        eventId: 'event-123',
        organizationId: 'org-valid',
        type: 'TEST_EVENT',
        contractId: 'contract-123',
        planVersion: 1,
        occurredAtUtc: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );

      registerFallbackValue(
        ForensicDossier(
          ledgerEntry: baseEntry,
          mapImageBytes: const [],
          savingsCents: 0,
        ),
      );

      when(
        () => mockTenantValidator.assertTenantMatches(
          payloadOrgId: any(named: 'payloadOrgId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async {});
    });

    test(
      'throws true SovereigntyViolationException on tenant mismatch (INV-1)',
      () async {
        final command = GenerateForensicDossierCommand(
          sessionId: 'session-123',
          operatorId: 'operator-123',
          jwtOrganizationId: 'org-valid',
          requestedOrganizationId: 'org-invalid', // Mismatch
          ledgerEntry: baseEntry,
          savingsCents: 150050,
          mapLat: -23.5505,
          mapLng: -46.6333,
        );

        // We explicitly test for the real domain exception, NOT a local shadow (Corrected Error #1)
        await expectLater(
          handler.handle(command),
          throwsA(isA<SovereigntyViolationException>()),
        );

        verifyZeroInteractions(mockMapService);
        verifyZeroInteractions(mockLogRepo);
        verifyZeroInteractions(mockPdfGenerator);
      },
    );

    test(
      'generates dossier and logs its hash successfully (Cadeia de Custódia Híbrida)',
      () async {
        when(
          () => mockMapService.getStaticMap(
            lat: any(named: 'lat'),
            lng: any(named: 'lng'),
            zoom: any(named: 'zoom'),
          ),
        ).thenAnswer((_) async => [1, 2, 3]);

        when(
          () => mockLogRepo.logGeneration(
            organizationId: any(named: 'organizationId'),
            slaLedgerEntryId: any(named: 'slaLedgerEntryId'),
            documentHash: any(named: 'documentHash'),
            operatorId: any(named: 'operatorId'),
          ),
        ).thenAnswer((_) async => {});

        when(
          () => mockPdfGenerator.generateDossier(any()),
        ).thenAnswer((_) async => [9, 9, 9]);

        final command = GenerateForensicDossierCommand(
          sessionId: 'session-123',
          operatorId: 'operator-123',
          jwtOrganizationId: 'org-valid',
          requestedOrganizationId: 'org-valid',
          ledgerEntry: baseEntry,
          savingsCents: 150050,
          mapLat: -23.5505,
          mapLng: -46.6333,
        );

        final result = await handler.handle(command);

        expect(result, equals([9, 9, 9]));

        verify(
          () => mockMapService.getStaticMap(
            lat: -23.5505,
            lng: -46.6333,
            zoom: 16,
          ),
        ).called(1);

        // Ensure the log was created
        verify(
          () => mockLogRepo.logGeneration(
            organizationId: 'org-valid',
            slaLedgerEntryId: 'event-123',
            documentHash: any(named: 'documentHash'),
            operatorId: 'operator-123',
          ),
        ).called(1);

        verify(() => mockPdfGenerator.generateDossier(any())).called(1);
      },
    );

    test(
      'catches infrastructure errors and wraps in IntegrityException safely',
      () async {
        when(
          () => mockMapService.getStaticMap(
            lat: any(named: 'lat'),
            lng: any(named: 'lng'),
            zoom: any(named: 'zoom'),
          ),
        ).thenThrow(Exception('MapTiler API quota exceeded'));

        final command = GenerateForensicDossierCommand(
          sessionId: 'session-123',
          operatorId: 'operator-123',
          jwtOrganizationId: 'org-valid',
          requestedOrganizationId: 'org-valid',
          ledgerEntry: baseEntry,
          savingsCents: 150050,
          mapLat: -23.5505,
          mapLng: -46.6333,
        );

        await expectLater(
          handler.handle(command),
          throwsA(isA<IntegrityException>()),
        );
      },
    );

    // ── Suspect B regression tests (INV-15 idempotency) ────────────────────

    test(
      'B1 [INV-15]: logRepository returning normally (23505 idempotent) does not block PDF return',
      () async {
        // Simulates the fixed behavior: repo already swallowed the 23505 unique
        // constraint and returned normally — handler must propagate PDF bytes.
        when(
          () => mockMapService.getStaticMap(
            lat: any(named: 'lat'),
            lng: any(named: 'lng'),
            zoom: any(named: 'zoom'),
          ),
        ).thenAnswer((_) async => [1, 2, 3]);

        when(
          () => mockLogRepo.logGeneration(
            organizationId: any(named: 'organizationId'),
            slaLedgerEntryId: any(named: 'slaLedgerEntryId'),
            documentHash: any(named: 'documentHash'),
            operatorId: any(named: 'operatorId'),
          ),
        ).thenAnswer((_) async {}); // idempotent success

        when(
          () => mockPdfGenerator.generateDossier(any()),
        ).thenAnswer((_) async => [7, 8, 9]);

        final command = GenerateForensicDossierCommand(
          sessionId: 'session-123',
          operatorId: 'operator-123',
          jwtOrganizationId: 'org-valid',
          requestedOrganizationId: 'org-valid',
          ledgerEntry: baseEntry,
          savingsCents: 150050,
          mapLat: -23.5505,
          mapLng: -46.6333,
        );

        final result = await handler.handle(command);

        expect(result, equals([7, 8, 9]));
        verify(() => mockPdfGenerator.generateDossier(any())).called(1);
      },
    );

    test(
      'B2 [INV-10]: non-idempotent logRepository failure is wrapped as IntegrityException',
      () async {
        // Simulates a real storage failure (e.g. FK violation, connection error)
        // that the repo converts to a domain exception — handler must wrap it.
        when(
          () => mockMapService.getStaticMap(
            lat: any(named: 'lat'),
            lng: any(named: 'lng'),
            zoom: any(named: 'zoom'),
          ),
        ).thenAnswer((_) async => [1, 2, 3]);

        when(
          () => mockLogRepo.logGeneration(
            organizationId: any(named: 'organizationId'),
            slaLedgerEntryId: any(named: 'slaLedgerEntryId'),
            documentHash: any(named: 'documentHash'),
            operatorId: any(named: 'operatorId'),
          ),
        ).thenThrow(
          const IntegrityException(
            'FK violation on pdf_dossier_logs',
            field: 'sla_ledger_entry_id',
          ),
        );

        when(
          () => mockPdfGenerator.generateDossier(any()),
        ).thenAnswer((_) async => [7, 8, 9]);

        final command = GenerateForensicDossierCommand(
          sessionId: 'session-123',
          operatorId: 'operator-123',
          jwtOrganizationId: 'org-valid',
          requestedOrganizationId: 'org-valid',
          ledgerEntry: baseEntry,
          savingsCents: 150050,
          mapLat: -23.5505,
          mapLng: -46.6333,
        );

        await expectLater(
          handler.handle(command),
          throwsA(isA<IntegrityException>()),
        );
      },
    );
  });
}
