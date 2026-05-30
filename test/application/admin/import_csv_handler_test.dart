import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/csv_foreign_key_validator.dart';
import 'package:veraprob/application/admin/csv_import_persister.dart';
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
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'dart:convert';

// Fakes
class FakeContractorRepository implements ContractorRepository {
  FakeContractorRepository([this._seed = const []]);
  final List<Contractor> _seed;

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  @override
  Future<Map<String, Contractor>> findByTaxIds(
    String organizationId,
    Set<String> taxIds,
  ) async {
    final wanted = taxIds.map(_digits).toSet();
    final out = <String, Contractor>{};
    for (final c in _seed) {
      if (c.organizationId != organizationId) continue;
      final d = _digits(c.taxId ?? '');
      if (wanted.contains(d)) out[d] = c;
    }
    return out;
  }

  @override
  Future<List<Contractor>> findByOrganization(String organizationId) async =>
      _seed.where((c) => c.organizationId == organizationId).toList();

  @override
  Future<Contractor?> findById(String organizationId, String id) async => null;

  @override
  Future<void> save(Contractor contractor) async {}

  @override
  Future<void> delete(String organizationId, String id) async {}

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async => rows.length;
}
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

/// Records the last persisted batch and echoes its size (rows actually
/// written), so handler assertions can verify the persistence delegation.
class FakeCsvImportPersister implements CsvImportPersister {
  int callCount = 0;
  String? lastEntity;
  List<Map<String, String>> lastRows = const [];

  @override
  Future<int> persist({
    required String organizationId,
    required String targetEntity,
    required List<Map<String, String>> rows,
    required CsvMappingTemplate template,
    required Map<String, Contractor> resolvedContractors,
  }) async {
    callCount++;
    lastEntity = targetEntity;
    lastRows = rows;
    return rows.length;
  }
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
        foreignKeyValidator: CsvForeignKeyValidator(
          contractorRepo: FakeContractorRepository(),
        ),
        persister: FakeCsvImportPersister(),
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

    test(
      'Bloco 1C: contract row with unknown contractor CNPJ is skipped (FK pre-flight)',
      () async {
        // Handler with a contractor owned by valid_org (CNPJ 11.222.333/0001-81).
        final fkHandler = ImportCsvHandler(
          tenantValidator: FakeTenantValidationService(),
          templateRepo: FakeCsvMappingTemplateRepository(),
          validator: CsvPreflightValidator(),
          persister: FakeCsvImportPersister(),
          foreignKeyValidator: CsvForeignKeyValidator(
            contractorRepo: FakeContractorRepository([
              Contractor(
                id: 'c1',
                organizationId: 'valid_org',
                name: 'ACME',
                taxId: '11222333000181',
                primaryEmail: 'a@b.com',
                contactName: 'John',
                createdAtUtc: DateTime.utc(2026, 1, 1),
              ),
            ]),
          ),
          dateTimeProvider: FakeDateTimeProvider(),
        );

        // Row 1 references the owned CNPJ → valid; row 2 references a valid but
        // unowned CNPJ → foreign_key_not_found, skipped.
        const csvText =
            'CODIGO,CNPJ\nCT-1,11222333000181\nCT-2,11444777000161';
        final command = ImportCsvCommand(
          sessionId: 'valid_session',
          organizationId: 'valid_org',
          targetEntity: 'contract',
          rawBytes: utf8.encode(csvText),
          adhocMappings: const [
            ColumnMapping(
              csvHeader: 'CODIGO',
              targetField: CsvTargetField.contractCode,
            ),
            ColumnMapping(
              csvHeader: 'CNPJ',
              targetField: CsvTargetField.contractorDocument,
            ),
          ],
        );

        final result = await fkHandler.handle(command);

        expect(result.totalProcessed, 2);
        expect(result.rowsSkipped, 1);
        expect(result.errors, hasLength(1));
        expect(result.errors.single.errorCode, 'foreign_key_not_found');
        expect(result.errors.single.rowIndex, 2);
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
        foreignKeyValidator: CsvForeignKeyValidator(
          contractorRepo: FakeContractorRepository(),
        ),
        persister: FakeCsvImportPersister(),
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
