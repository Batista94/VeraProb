import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/shared/security_assertion_service.dart';

/// Represents a specific validation error for a row in the CSV.
class CsvRowError extends Equatable {
  final int rowIndex; // 1-indexed (matches CSV line)
  final String csvHeader;
  final String targetField;
  final String errorCode;
  final String message;

  const CsvRowError({
    required this.rowIndex,
    required this.csvHeader,
    required this.targetField,
    required this.errorCode,
    required this.message,
  });

  @override
  List<Object?> get props => [
    rowIndex,
    csvHeader,
    targetField,
    errorCode,
    message,
  ];
}

/// Result of pre-flight CSV validation.
class CsvPreflightReport extends Equatable {
  final int totalRows;
  final int validRows;
  final List<CsvRowError> errors;

  bool get hasErrors => errors.isNotEmpty;
  bool get isClean => errors.isEmpty;

  const CsvPreflightReport({
    required this.totalRows,
    required this.validRows,
    required this.errors,
  });

  @override
  List<Object?> get props => [totalRows, validRows, errors];
}

/// Pure Dart domain service to validate parsed CSV rows against a template.
class CsvPreflightValidator {
  /// Validates a list of parsed CSV rows against the mapping template.
  ///
  /// Emenda 1: Applies SecurityAssertionService checks (CSV Injection, Stored XSS).
  /// Emenda 2: Collects all errors but allows valid rows to be identified for Partial Import.
  CsvPreflightReport validate(
    List<Map<String, String>> rows,
    CsvMappingTemplate template,
  ) {
    final errors = <CsvRowError>[];
    int validRowsCount = 0;

    // Track documents to find duplicates in batch (e.g., CNPJ/CPF)
    final documentTracker =
        <String, int>{}; // document value -> first seen row index

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowIndex = i + 1; // 1-indexed for user readability
      bool rowHasError = false;

      for (final mapping in template.columnMappings) {
        final rawValue = row[mapping.csvHeader];

        // 1. Check if source header is missing entirely
        if (rawValue == null) {
          errors.add(
            CsvRowError(
              rowIndex: rowIndex,
              csvHeader: mapping.csvHeader,
              targetField: mapping.targetField.dbValue,
              errorCode: 'missing_source',
              message: 'Coluna obrigatória ausente no arquivo CSV.',
            ),
          );
          rowHasError = true;
          continue;
        }

        final trimmedValue = rawValue.trim();

        // 2. Check required field
        if (mapping.required && trimmedValue.isEmpty) {
          errors.add(
            CsvRowError(
              rowIndex: rowIndex,
              csvHeader: mapping.csvHeader,
              targetField: mapping.targetField.dbValue,
              errorCode: 'required',
              message: 'Valor obrigatório não preenchido.',
            ),
          );
          rowHasError = true;
          continue;
        }

        // If empty and not required, skip further checks for this column
        if (trimmedValue.isEmpty) continue;

        // 3. Security Checks (Emenda 1)
        try {
          SecurityAssertionService.assertNoCsvInjection(
            trimmedValue,
            mapping.csvHeader,
          );
        } catch (e) {
          errors.add(
            CsvRowError(
              rowIndex: rowIndex,
              csvHeader: mapping.csvHeader,
              targetField: mapping.targetField.dbValue,
              errorCode: 'injection_detected',
              message:
                  'Valor bloqueado por segurança (fórmula suspeita detectada).',
            ),
          );
          rowHasError = true;
          continue;
        }

        final sanitizedValue = SecurityAssertionService.sanitizeHtml(
          trimmedValue,
        );

        // 4. Domain-specific formatting & structural checks
        if (mapping.targetField == CsvTargetField.capacity) {
          if (int.tryParse(sanitizedValue) == null) {
            errors.add(
              CsvRowError(
                rowIndex: rowIndex,
                csvHeader: mapping.csvHeader,
                targetField: mapping.targetField.dbValue,
                errorCode: 'invalid_number',
                message: 'Capacidade deve ser um número inteiro válido.',
              ),
            );
            rowHasError = true;
          }
        } else if (mapping.targetField == CsvTargetField.latitude ||
            mapping.targetField == CsvTargetField.longitude) {
          final val = double.tryParse(sanitizedValue);
          if (val == null ||
              (mapping.targetField == CsvTargetField.latitude &&
                  (val < -90 || val > 90)) ||
              (mapping.targetField == CsvTargetField.longitude &&
                  (val < -180 || val > 180))) {
            errors.add(
              CsvRowError(
                rowIndex: rowIndex,
                csvHeader: mapping.csvHeader,
                targetField: mapping.targetField.dbValue,
                errorCode: 'invalid_coordinate',
                message:
                    'Coordenada geolocalizada fora dos limites permitidos.',
              ),
            );
            rowHasError = true;
          }
        } else if (mapping.targetField == CsvTargetField.operatorDocument ||
            mapping.targetField == CsvTargetField.contractorDocument) {
          // Simple duplication check in batch
          if (documentTracker.containsKey(sanitizedValue)) {
            final firstRow = documentTracker[sanitizedValue];
            errors.add(
              CsvRowError(
                rowIndex: rowIndex,
                csvHeader: mapping.csvHeader,
                targetField: mapping.targetField.dbValue,
                errorCode: 'duplicate_in_batch',
                message:
                    'Documento duplicado neste mesmo arquivo (visto na linha $firstRow).',
              ),
            );
            rowHasError = true;
          } else {
            documentTracker[sanitizedValue] = rowIndex;
          }
          // Note: Real CNPJ mod-11 check logic would go here
        } else if (mapping.targetField == CsvTargetField.startDate ||
            mapping.targetField == CsvTargetField.endDate) {
          // Date parsing attempt based on hint (simplified)
          if (DateTime.tryParse(sanitizedValue) == null &&
              mapping.formatHint == null) {
            errors.add(
              CsvRowError(
                rowIndex: rowIndex,
                csvHeader: mapping.csvHeader,
                targetField: mapping.targetField.dbValue,
                errorCode: 'invalid_date',
                message:
                    'Data inválida ou em formato não reconhecido (use padrão ISO-8601 ou especifique formato).',
              ),
            );
            rowHasError = true;
          }
        }
      }

      if (!rowHasError) {
        validRowsCount++;
      }
    }

    return CsvPreflightReport(
      totalRows: rows.length,
      validRows: validRowsCount,
      errors: errors,
    );
  }
}
