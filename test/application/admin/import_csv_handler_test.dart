import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/application/admin/import_csv_handler.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/i_csv_mapping_template_repository.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'dart:convert';

// Fakes
class FakeTenantValidationService implements TenantValidationService {
  @override
  Future<void> assertTenantMatches({
    required String payloadOrgId,
    required String sessionId,
  }) async {
    if (payloadOrgId != 'valid_org' || sessionId != 'valid_session') {
      throw const SovereigntyViolationException(
        payloadOrgId: 'invalid',
        jwtOrgId: 'valid_org',
      );
    }
  }

  @override
  void verifySourceOwnership({
    required String requesterOrgId,
    String? resourceId,
    required String resourceOrgId,
    String? resourceType,
  }) {}
}

class FakeCsvMappingTemplateRepository
    implements ICsvMappingTemplateRepository {
  final List<CsvMappingTemplate> _templates = [];

  @override
  Future<CsvMappingTemplate> createTemplate(CsvMappingTemplate template) async {
    _templates.add(template);
    return template;
  }

  @override
  Future<void> deleteTemplate(
    String templateId, {
    required String organizationId,
  }) async {}

  @override
  Future<CsvMappingTemplate?> getDefaultTemplate({
    required String organizationId,
    required String targetEntity,
  }) async => null;

  @override
  Future<List<CsvMappingTemplate>> getTemplates({
    required String organizationId,
    String? targetEntity,
  }) async {
    return _templates
        .where((t) => targetEntity == null || t.targetEntity == targetEntity)
        .toList();
  }

  @override
  Future<CsvMappingTemplate> updateTemplate(
    CsvMappingTemplate template,
  ) async => template;
}

class FakeDateTimeProvider implements IDateTimeProvider {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 1, 1);

  @override
  DateTime nowBrazil() => DateTime(2026, 1, 1);
}

void main() {
  group('ImportCsvHandler', () {
    late ImportCsvHandler handler;
    late FakeCsvMappingTemplateRepository repo;

    setUp(() {
      repo = FakeCsvMappingTemplateRepository();
      handler = ImportCsvHandler(
        tenantValidator: FakeTenantValidationService(),
        templateRepo: repo,
        validator: CsvPreflightValidator(),
        dateTimeProvider: FakeDateTimeProvider(),
      );
    });

    test(
      'Hacking/Adverse: Rejects EXE/MZ binary file at orchestrator level (Emenda 1)',
      () async {
        const command = ImportCsvCommand(
          sessionId: 'valid_session',
          organizationId: 'valid_org',
          targetEntity: 'asset',
          rawBytes: [0x4D, 0x5A, 0x90, 0x00], // MZ header
          adhocMappings: [
            ColumnMapping(
              csvHeader: 'PLACA',
              targetField: CsvTargetField.identifier,
            ),
          ],
        );

        expect(
          () => handler.handle(command),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Executable'),
            ),
          ),
        );
      },
    );

    test(
      'Partial Import strategy (Emenda 2) inserts valid and skips invalid',
      () async {
        const csvText =
            'PLACA,CAPACIDADE\nABC-1234,40\nDEF-5678,quarenta\nGHI-9012,42';
        final command = ImportCsvCommand(
          sessionId: 'valid_session',
          organizationId: 'valid_org',
          targetEntity: 'asset',
          rawBytes: utf8.encode(csvText),
          adhocMappings: const [
            ColumnMapping(
              csvHeader: 'PLACA',
              targetField: CsvTargetField.identifier,
            ),
            ColumnMapping(
              csvHeader: 'CAPACIDADE',
              targetField: CsvTargetField.capacity,
            ),
          ],
        );

        final result = await handler.handle(command);

        expect(result.totalProcessed, 3);
        expect(result.rowsImported, 2); // ABC and GHI
        expect(result.rowsSkipped, 1); // DEF (invalid capacity)
        expect(result.hasErrors, true);
        expect(result.errors.length, 1);
        expect(result.errors.first.rowIndex, 2);
      },
    );
  });

  group('Tenant Isolation (INV-1, INV-22)', () {
    late ImportCsvHandler handler;

    setUp(() {
      handler = ImportCsvHandler(
        tenantValidator: FakeTenantValidationService(),
        templateRepo: FakeCsvMappingTemplateRepository(),
        validator: CsvPreflightValidator(),
        dateTimeProvider: FakeDateTimeProvider(),
      );
    });

    test(
      'Hacking/Adverse: Fails fast if organization_id does not match session',
      () async {
        final command = ImportCsvCommand(
          sessionId: 'valid_session',
          organizationId: 'malicious_org',
          targetEntity: 'asset',
          rawBytes: utf8.encode('PLACA\nABC-1234'),
          adhocMappings: const [
            ColumnMapping(
              csvHeader: 'PLACA',
              targetField: CsvTargetField.identifier,
            ),
          ],
        );

        expect(
          () => handler.handle(command),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );
  });
}
