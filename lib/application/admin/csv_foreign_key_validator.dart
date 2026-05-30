import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';

/// Outcome of an async foreign-key pre-flight pass.
///
/// [errors] are merged with the synchronous [CsvPreflightReport] errors by the
/// handler. [resolvedContractors] (keyed by digit-normalised CNPJ) lets the
/// row mapper populate denormalised columns (e.g. `contracts.contractor_name`)
/// from the tenant-owned contractor without a second lookup.
class CsvForeignKeyResult {
  const CsvForeignKeyResult({
    required this.errors,
    required this.resolvedContractors,
  });

  final List<CsvRowError> errors;
  final Map<String, Contractor> resolvedContractors;
}

/// Async FK existence validator for CSV imports.
///
/// Runs AFTER the synchronous [CsvPreflightValidator] and BEFORE persistence.
/// Tenant-scoped: a referenced key that exists only in another tenant yields
/// the exact same generic error as a genuine miss — no cross-tenant existence
/// leak (INV-22 / INV-26). Lookups are batched (INV-16).
///
/// Today only the `contract` entity carries an FK rule (`contractorDocument`
/// → contractors). The shape is generic so future entity FKs slot in here.
class CsvForeignKeyValidator {
  CsvForeignKeyValidator({required ContractorRepository contractorRepo})
    : _contractorRepo = contractorRepo;

  final ContractorRepository _contractorRepo;

  /// Generic, oracle-safe message. Identical for "missing" and "other tenant".
  static const String _fkNotFoundMessage =
      'Contratante não encontrado para o documento informado.';

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  Future<CsvForeignKeyResult> validate({
    required String organizationId,
    required String targetEntity,
    required List<Map<String, String>> rows,
    required CsvMappingTemplate template,
  }) async {
    if (targetEntity != 'contract') {
      return const CsvForeignKeyResult(errors: [], resolvedContractors: {});
    }

    final docHeader = _headerFor(template, CsvTargetField.contractorDocument);
    if (docHeader == null) {
      return const CsvForeignKeyResult(errors: [], resolvedContractors: {});
    }

    final distinct = <String>{};
    for (final row in rows) {
      final d = _digits(row[docHeader] ?? '');
      if (d.isNotEmpty) distinct.add(d);
    }

    final owned = await _contractorRepo.findByTaxIds(organizationId, distinct);

    final errors = <CsvRowError>[];
    for (var i = 0; i < rows.length; i++) {
      final d = _digits(rows[i][docHeader] ?? '');
      if (d.isEmpty || owned.containsKey(d)) continue;
      errors.add(
        CsvRowError(
          rowIndex: i + 1,
          csvHeader: docHeader,
          targetField: 'contractor_document',
          errorCode: 'foreign_key_not_found',
          message: _fkNotFoundMessage,
        ),
      );
    }

    return CsvForeignKeyResult(errors: errors, resolvedContractors: owned);
  }

  String? _headerFor(CsvMappingTemplate template, CsvTargetField field) {
    for (final mapping in template.columnMappings) {
      if (mapping.targetField == field) return mapping.csvHeader;
    }
    return null;
  }
}
