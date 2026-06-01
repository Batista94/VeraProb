import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/csv_foreign_key_validator.dart';
import 'package:veraprob/application/admin/csv_import_persister.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/application/admin/import_csv_handler.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/domain/admin/i_csv_mapping_template_repository.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeCsvMappingTemplateRepository
    implements ICsvMappingTemplateRepository {
  String? capturedOrgId;
  String? capturedEntity;

  final List<CsvMappingTemplate> _templates;

  _FakeCsvMappingTemplateRepository({List<CsvMappingTemplate>? templates})
    : _templates = templates ?? const [];

  @override
  Future<List<CsvMappingTemplate>> getTemplates({
    required String organizationId,
    String? targetEntity,
  }) async {
    capturedOrgId = organizationId;
    capturedEntity = targetEntity;
    return _templates;
  }

  @override
  Future<CsvMappingTemplate?> getDefaultTemplate({
    required String organizationId,
    required String targetEntity,
  }) async => null;

  @override
  Future<CsvMappingTemplate> createTemplate(
    CsvMappingTemplate template,
  ) async => template;

  @override
  Future<CsvMappingTemplate> updateTemplate(
    CsvMappingTemplate template,
  ) async => template;

  @override
  Future<void> deleteTemplate(
    String templateId, {
    required String organizationId,
  }) async {}
}

/// Returns a user whose [tenantId] is always 'other-org',
/// causing TenantValidationService to detect a mismatch.
class _WrongOrgAuthRepository implements IAuthRepository {
  @override
  bool get isAuthenticated => true;

  @override
  Stream<bool> get authStatusStream => const Stream.empty();

  @override
  Future<String> signInWithPassword({
    required String email,
    required String password,
  }) async => 'user-id';

  @override
  Future<String> signUpWithPassword({
    required String email,
    required String password,
  }) async => 'user-id';

  @override
  Future<void> signOut() async {}

  @override
  Future<void> refreshSession() async {}

  @override
  Future<AuthUser?> getCurrentUser() async => null;

  @override
  Future<AuthUser?> getUserBySessionId(String sessionId) async {
    return const AuthUser(
      id: 'user-id',
      email: 'a@b.com',
      tenantId: 'other-org',
    );
  }
}

class _UtcDateTimeProvider extends IDateTimeProvider {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 1, 1);

  @override
  DateTime nowBrazil() => DateTime(2026, 1, 1);
}

// ── Provider container helper ─────────────────────────────────────────────────

ProviderContainer _makeContainer({
  String? orgId = 'org-test-1',
  String? sessionId = 'session-test-1',
  _FakeCsvMappingTemplateRepository? repo,
  ImportCsvHandler? handler,
}) {
  return ProviderContainer(
    overrides: [
      currentOrganizationIdProvider.overrideWith((_) => orgId),
      currentSessionIdProvider.overrideWith((_) => sessionId),
      if (repo != null)
        csvMappingTemplateRepositoryProvider.overrideWith((_) => repo),
      if (handler != null)
        importCsvHandlerProvider.overrideWith((_) => handler),
    ],
  );
}

CsvPreflightReport _emptyReport() {
  final template = CsvMappingTemplate(
    id: '',
    organizationId: 'org-test-1',
    name: 'AdHoc',
    targetEntity: 'operator',
    columnMappings: const [],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  return CsvPreflightValidator().validate([], template);
}

/// Builds an [ImportCsvHandler] backed by [_WrongOrgAuthRepository].
/// [handle] will throw [SovereigntyViolationException] from assertTenantMatches.
ImportCsvHandler _mismatchHandler() {
  return ImportCsvHandler(
    tenantValidator: TenantValidationService(
      authRepository: _WrongOrgAuthRepository(),
    ),
    templateRepo: _FakeCsvMappingTemplateRepository(),
    validator: CsvPreflightValidator(),
    foreignKeyValidator: CsvForeignKeyValidator(
      contractorRepo: _NoopContractorRepository(),
    ),
    persister: _NoopCsvImportPersister(),
    dateTimeProvider: _UtcDateTimeProvider(),
  );
}

/// Persistence is never reached — the handler fails fast at the tenant check.
class _NoopCsvImportPersister implements CsvImportPersister {
  @override
  Future<int> persist({
    required String organizationId,
    required String targetEntity,
    required List<Map<String, String>> rows,
    required CsvMappingTemplate template,
    required Map<String, Contractor> resolvedContractors,
  }) async => 0;
}

class _NoopContractorRepository implements ContractorRepository {
  @override
  Future<Map<String, Contractor>> findByTaxIds(
    String organizationId,
    Set<String> taxIds,
  ) async => const {};

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async => rows.length;

  @override
  Future<List<Contractor>> findByOrganization(String organizationId) async =>
      const [];

  @override
  Future<Contractor?> findById(String organizationId, String id) async => null;

  @override
  Future<void> save(Contractor contractor) async {}

  @override
  Future<void> delete(String organizationId, String id) async {}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('csvTemplatesProvider (family)', () {
    // P1 — passes orgId from JWT to repo
    test(
      'P1: injects orgId from currentOrganizationIdProvider into repo',
      () async {
        final repo = _FakeCsvMappingTemplateRepository();
        final container = _makeContainer(orgId: 'tenant-abc', repo: repo);
        addTearDown(container.dispose);

        await container.read(csvTemplatesProvider('operator').future);

        expect(repo.capturedOrgId, equals('tenant-abc'));
        expect(repo.capturedEntity, equals('operator'));
      },
    );

    // P1b — returns empty when orgId is null (no session)
    test('P1b: returns empty list when orgId is null', () async {
      final container = _makeContainer(orgId: null);
      addTearDown(container.dispose);

      final templates = await container.read(
        csvTemplatesProvider('operator').future,
      );
      expect(templates, isEmpty);
    });
  });

  group('CsvImportFlowNotifier', () {
    // P2 — submit with tenant mismatch → CsvImportError (not crash)
    test('P2: submit with tenant mismatch yields CsvImportError', () async {
      // SovereigntyViolationException from assertTenantMatches is caught
      // by catch(_) in notifier.submit() → sets generic Portuguese message.
      final container = _makeContainer(handler: _mismatchHandler());
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final report = _emptyReport();

      // ignore: invalid_use_of_protected_member
      notifier.state = CsvImportValidated(
        targetEntity: 'operator',
        fileName: 'test.csv',
        headers: const ['PLACA'],
        previewRows: const [],
        allRows: const [],
        rawBytes: const [0x74, 0x65, 0x73, 0x74], // "test" — plain text magic
        mappings: const {
          'PLACA': ColumnMapping(
            csvHeader: 'PLACA',
            targetField: CsvTargetField.identifier,
          ),
        },
        report: report,
      );

      await notifier.submit();

      final finalState = container.read(csvImportFlowProvider);
      expect(finalState, isA<CsvImportError>());
      final err = finalState as CsvImportError;
      expect(
        err.message,
        equals('Sessão expirada ou inválida. Por favor, faça login novamente.'),
      );
    });

    test(
      'P2b: submit error preserves CsvImportValidated as previousState',
      () async {
        final container = _makeContainer(handler: _mismatchHandler());
        addTearDown(container.dispose);

        final notifier = container.read(csvImportFlowProvider.notifier);
        final report = _emptyReport();

        final initialValidated = CsvImportValidated(
          targetEntity: 'operator',
          fileName: 'test.csv',
          headers: const ['PLACA'],
          previewRows: const [],
          allRows: const [],
          rawBytes: const [0x74, 0x65, 0x73, 0x74],
          mappings: const {
            'PLACA': ColumnMapping(
              csvHeader: 'PLACA',
              targetField: CsvTargetField.identifier,
            ),
          },
          report: report,
        );

        // ignore: invalid_use_of_protected_member
        notifier.state = initialValidated;

        await notifier.submit();

        final finalState = container.read(csvImportFlowProvider);
        expect(finalState, isA<CsvImportError>());
        final err = finalState as CsvImportError;
        expect(err.previousState, equals(initialValidated));
      },
    );

    // P3 — goBack from CsvImportValidated → CsvImportMapped (not Validated)
    test('P3: goBack from CsvImportValidated yields CsvImportMapped', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final report = _emptyReport();

      // ignore: invalid_use_of_protected_member
      notifier.state = CsvImportValidated(
        targetEntity: 'operator',
        fileName: 'test.csv',
        headers: const ['PLACA'],
        previewRows: const [],
        allRows: const [],
        rawBytes: const [],
        mappings: const {},
        report: report,
      );

      notifier.goBack();

      final s = container.read(csvImportFlowProvider);
      expect(s, isA<CsvImportMapped>());
      expect(s, isNot(isA<CsvImportValidated>()));
    });

    // P4 — validate with no active mappings sets error, never advances to Validated
    test('P4: validate with all-null mappings sets CsvImportError', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);

      // ignore: invalid_use_of_protected_member
      notifier.state = const CsvImportMapped(
        targetEntity: 'operator',
        fileName: 'test.csv',
        headers: ['PLACA'],
        previewRows: [],
        allRows: [],
        rawBytes: [],
        mappings: {'PLACA': null},
      );

      notifier.validate();

      final s = container.read(csvImportFlowProvider);
      expect(s, isA<CsvImportError>());
      expect(s, isNot(isA<CsvImportValidated>()));
    });

    // ── Coverage gate (CT01 null-name regression) ──────────────────────────

    // CT01 repro: contractor file with only externalId mapped → validate must
    // block (validRows 0, unmapped_required) instead of letting submit reach
    // batch_upsert_contractors with a null name (23502).
    test('validate blocks contractor import missing required name', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);

      // ignore: invalid_use_of_protected_member
      notifier.state = const CsvImportMapped(
        targetEntity: 'contractor',
        fileName: 'contratantes.csv',
        headers: ['externalId'],
        previewRows: [],
        allRows: [
          {'externalId': 'CTR-1'},
        ],
        mappings: {
          'externalId': ColumnMapping(
            csvHeader: 'externalId',
            targetField: CsvTargetField.externalId,
          ),
        },
        rawBytes: [],
      );

      notifier.validate();

      final s = container.read(csvImportFlowProvider);
      expect(s, isA<CsvImportValidated>());
      final report = (s as CsvImportValidated).report;
      expect(report.validRows, 0);
      expect(report.hasErrors, isTrue);
      expect(
        report.errors.map((e) => e.errorCode),
        contains('unmapped_required'),
      );
    });

    // Happy path: all required fields mapped + filled → ready to import.
    test('validate passes when all required contractor fields mapped', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);

      // ignore: invalid_use_of_protected_member
      notifier.state = const CsvImportMapped(
        targetEntity: 'contractor',
        fileName: 'contratantes.csv',
        headers: ['name', 'doc', 'email', 'contact'],
        previewRows: [],
        allRows: [
          {
            'name': 'Alfa Ltda',
            'doc': '11.222.333/0001-81',
            'email': 'a@b.com',
            'contact': 'Carlos',
          },
        ],
        mappings: {
          'name': ColumnMapping(
            csvHeader: 'name',
            targetField: CsvTargetField.contractorName,
          ),
          'doc': ColumnMapping(
            csvHeader: 'doc',
            targetField: CsvTargetField.contractorDocument,
          ),
          'email': ColumnMapping(
            csvHeader: 'email',
            targetField: CsvTargetField.contractorEmail,
          ),
          'contact': ColumnMapping(
            csvHeader: 'contact',
            targetField: CsvTargetField.contractorContactName,
          ),
        },
        rawBytes: [],
      );

      notifier.validate();

      final s = container.read(csvImportFlowProvider);
      expect(s, isA<CsvImportValidated>());
      final report = (s as CsvImportValidated).report;
      expect(report.isClean, isTrue);
      expect(report.validRows, 1);
    });

    // A mapped-but-blank required cell is caught per-row (required flag is
    // forced on required fields by _activeMappings).
    test('validate flags a blank required cell on a mapped column', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);

      // ignore: invalid_use_of_protected_member
      notifier.state = const CsvImportMapped(
        targetEntity: 'contractor',
        fileName: 'contratantes.csv',
        headers: ['name', 'email', 'contact'],
        previewRows: [],
        allRows: [
          {'name': '   ', 'email': 'a@b.com', 'contact': 'Carlos'},
        ],
        mappings: {
          'name': ColumnMapping(
            csvHeader: 'name',
            targetField: CsvTargetField.contractorName,
          ),
          'email': ColumnMapping(
            csvHeader: 'email',
            targetField: CsvTargetField.contractorEmail,
          ),
          'contact': ColumnMapping(
            csvHeader: 'contact',
            targetField: CsvTargetField.contractorContactName,
          ),
        },
        rawBytes: [],
      );

      notifier.validate();

      final s = container.read(csvImportFlowProvider);
      final report = (s as CsvImportValidated).report;
      expect(report.validRows, 0);
      expect(report.errors.map((e) => e.errorCode), contains('required'));
    });

    // goBack from CsvImportMapped → CsvImportInitial
    test('goBack from CsvImportMapped yields CsvImportInitial', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);

      // ignore: invalid_use_of_protected_member
      notifier.state = const CsvImportMapped(
        targetEntity: 'operator',
        fileName: 'test.csv',
        headers: ['PLACA'],
        previewRows: [],
        allRows: [],
        rawBytes: [],
        mappings: {},
      );

      notifier.goBack();

      final s = container.read(csvImportFlowProvider);
      expect(s, isA<CsvImportInitial>());
    });
  });
}
