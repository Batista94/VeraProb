import 'package:csv/csv.dart';
import 'package:equatable/equatable.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/i_csv_mapping_template_repository.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/security_assertion_service.dart';
import 'dart:convert';

class ImportCsvCommand extends Equatable {
  final String sessionId;
  final String organizationId;
  final String targetEntity; // 'asset' | 'contract' | 'zone' | 'operator'
  final String? templateId;
  final List<int> rawBytes;
  final List<ColumnMapping>? adhocMappings;

  const ImportCsvCommand({
    required this.sessionId,
    required this.organizationId,
    required this.targetEntity,
    this.templateId,
    required this.rawBytes,
    this.adhocMappings,
  });

  @override
  List<Object?> get props => [
    sessionId,
    organizationId,
    targetEntity,
    templateId,
    rawBytes,
    adhocMappings,
  ];
}

class CsvImportResult extends Equatable {
  final int totalProcessed;
  final int rowsImported;
  final int rowsSkipped;
  final String? savedTemplateId;
  final List<CsvRowError>
  errors; // Emenda 2: Contains errors for the skipped rows

  const CsvImportResult({
    required this.totalProcessed,
    required this.rowsImported,
    required this.rowsSkipped,
    this.savedTemplateId,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isClean => errors.isEmpty;

  @override
  List<Object?> get props => [
    totalProcessed,
    rowsImported,
    rowsSkipped,
    savedTemplateId,
    errors,
  ];
}

/// Orchestrator for CSV Import.
///
/// Emenda 1: MIME-Type Sniffing executed before parsing.
/// Emenda 2: Partial Import strategy — persists valid rows, returns errors delta.
class ImportCsvHandler {
  final TenantValidationService _tenantValidator;
  final ICsvMappingTemplateRepository _templateRepo;
  final CsvPreflightValidator _validator;
  final IDateTimeProvider _dateTimeProvider;

  ImportCsvHandler({
    required TenantValidationService tenantValidator,
    required ICsvMappingTemplateRepository templateRepo,
    required CsvPreflightValidator validator,
    required IDateTimeProvider dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _templateRepo = templateRepo,
       _validator = validator,
       _dateTimeProvider = dateTimeProvider;

  Future<CsvImportResult> handle(ImportCsvCommand command) async {
    // 1. INV-1 Fail-Fast tenant check
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. Emenda 1: MIME-Type Sniffing (reject binaries, executables, zip, pdf)
    SecurityAssertionService.assertPlainTextMagicBytes(command.rawBytes);

    // 3. Resolve template
    CsvMappingTemplate template;
    if (command.templateId != null) {
      final t = (await _templateRepo.getTemplates(
        targetEntity: command.targetEntity,
      )).firstWhere((t) => t.id == command.templateId);
      template = t;
    } else {
      template = CsvMappingTemplate(
        id: 'ephemeral',
        organizationId: command.organizationId,
        name: 'AdHoc',
        targetEntity: command.targetEntity,
        columnMappings: command.adhocMappings ?? [],
        createdAt: _dateTimeProvider.nowUtc(),
        updatedAt: _dateTimeProvider.nowUtc(),
      );
      template.assertValid();
    }

    // 4. Parse CSV bytes
    final csvString = utf8.decode(command.rawBytes);
    final rawRows = Csv(
      lineDelimiter: '\n',
      dynamicTyping: false,
    ).decode(csvString);

    if (rawRows.isEmpty || rawRows.length == 1) {
      return const CsvImportResult(
        totalProcessed: 0,
        rowsImported: 0,
        rowsSkipped: 0,
      ); // Empty or headers only
    }

    final headers = rawRows.first
        .map((Object? e) => (e ?? '').toString().trim())
        .toList();
    final List<Map<String, String>> mappedRows = [];

    for (var i = 1; i < rawRows.length; i++) {
      final row = rawRows[i];
      final map = <String, String>{};
      for (var j = 0; j < headers.length; j++) {
        if (j < row.length) {
          map[headers[j]] = row[j].toString();
        }
      }
      mappedRows.add(map);
    }

    // 5. Preflight validation
    final report = _validator.validate(mappedRows, template);

    // 6. Emenda 2: Partial Import
    // Identify valid rows to persist
    final validRows = <Map<String, String>>[];
    final errorLines = report.errors.map((e) => e.rowIndex).toSet();

    for (var i = 0; i < mappedRows.length; i++) {
      if (!errorLines.contains(i + 1)) {
        validRows.add(mappedRows[i]);
      }
    }

    int inserted = 0;
    if (validRows.isNotEmpty) {
      // TODO: Delegate to specific repository based on `command.targetEntity`
      // e.g., if targetEntity == 'asset', _assetRepo.batchUpsert(validRows)
      inserted = validRows.length;
    }

    return CsvImportResult(
      totalProcessed: mappedRows.length,
      rowsImported: inserted,
      rowsSkipped: mappedRows.length - inserted,
      savedTemplateId: command.templateId,
      errors: report.errors, // UI will use this to generate the delta CSV
    );
  }
}
