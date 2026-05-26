import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
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

/// Library-private result carrier for [CsvPreflightValidator._preprocessField].
class _FieldPreprocessResult {
  final String? sanitizedValue;
  final CsvRowError? error;
  final bool _isSkip;

  const _FieldPreprocessResult._({
    this.sanitizedValue,
    this.error,
    bool isSkip = false,
  }) : _isSkip = isSkip;

  const _FieldPreprocessResult.skip() : this._(isSkip: true);

  const _FieldPreprocessResult.withError(CsvRowError error)
    : this._(error: error);

  const _FieldPreprocessResult.value(String sanitizedValue)
    : this._(sanitizedValue: sanitizedValue);

  bool get isSkip => _isSkip;
  bool get isError => error != null;
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
    final documentTracker = <String, int>{};
    int validRowsCount = 0;

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowIndex = i + 1;
      bool rowHasError = false;

      for (final mapping in template.columnMappings) {
        final preprocessed = _preprocessField(
          row[mapping.csvHeader],
          mapping,
          rowIndex,
        );

        if (preprocessed.isSkip) continue;

        if (preprocessed.isError) {
          errors.add(preprocessed.error!);
          rowHasError = true;
          continue;
        }

        final fieldError = _validateFieldType(
          preprocessed.sanitizedValue!,
          mapping,
          rowIndex,
          documentTracker,
        );

        if (fieldError != null) {
          errors.add(fieldError);
          rowHasError = true;
        }
      }

      if (!rowHasError) validRowsCount++;
    }

    return CsvPreflightReport(
      totalRows: rows.length,
      validRows: validRowsCount,
      errors: errors,
    );
  }

  _FieldPreprocessResult _preprocessField(
    String? rawValue,
    ColumnMapping mapping,
    int rowIndex,
  ) {
    if (rawValue == null) {
      return _FieldPreprocessResult.withError(
        CsvRowError(
          rowIndex: rowIndex,
          csvHeader: mapping.csvHeader,
          targetField: mapping.targetField.dbValue,
          errorCode: 'missing_source',
          message: 'Coluna obrigatória ausente no arquivo CSV.',
        ),
      );
    }

    final trimmedValue = rawValue.trim();

    if (mapping.required && trimmedValue.isEmpty) {
      return _FieldPreprocessResult.withError(
        CsvRowError(
          rowIndex: rowIndex,
          csvHeader: mapping.csvHeader,
          targetField: mapping.targetField.dbValue,
          errorCode: 'required',
          message: 'Valor obrigatório não preenchido.',
        ),
      );
    }

    if (trimmedValue.isEmpty) return const _FieldPreprocessResult.skip();

    try {
      SecurityAssertionService.assertNoCsvInjection(
        trimmedValue,
        mapping.csvHeader,
      );
    } catch (_) {
      return _FieldPreprocessResult.withError(
        CsvRowError(
          rowIndex: rowIndex,
          csvHeader: mapping.csvHeader,
          targetField: mapping.targetField.dbValue,
          errorCode: 'injection_detected',
          message:
              'Valor bloqueado por segurança (fórmula suspeita detectada).',
        ),
      );
    }

    return _FieldPreprocessResult.value(
      SecurityAssertionService.sanitizeHtml(trimmedValue),
    );
  }

  CsvRowError? _validateFieldType(
    String value,
    ColumnMapping mapping,
    int rowIndex,
    Map<String, int> documentTracker,
  ) {
    if (mapping.targetField == CsvTargetField.capacity) {
      return _validateCapacity(value, mapping, rowIndex);
    }
    if (_coordinateFields.contains(mapping.targetField)) {
      return _validateCoordinate(value, mapping, rowIndex);
    }
    if (_documentFields.contains(mapping.targetField)) {
      return _validateDocument(value, mapping, rowIndex, documentTracker);
    }
    if (_dateFields.contains(mapping.targetField)) {
      return _validateDate(value, mapping, rowIndex);
    }
    return null;
  }

  static const Set<CsvTargetField> _coordinateFields = {
    CsvTargetField.latitude,
    CsvTargetField.longitude,
  };
  static const Set<CsvTargetField> _documentFields = {
    CsvTargetField.operatorDocument,
    CsvTargetField.contractorDocument,
  };
  static const Set<CsvTargetField> _dateFields = {
    CsvTargetField.startDate,
    CsvTargetField.endDate,
  };

  CsvRowError? _validateCapacity(
    String value,
    ColumnMapping mapping,
    int rowIndex,
  ) {
    if (int.tryParse(value) == null) {
      return CsvRowError(
        rowIndex: rowIndex,
        csvHeader: mapping.csvHeader,
        targetField: mapping.targetField.dbValue,
        errorCode: 'invalid_number',
        message: 'Capacidade deve ser um número inteiro válido.',
      );
    }
    return null;
  }

  CsvRowError? _validateCoordinate(
    String value,
    ColumnMapping mapping,
    int rowIndex,
  ) {
    final val = num.tryParse(value);
    final isInvalid =
        val == null ||
        (mapping.targetField == CsvTargetField.latitude &&
            _isLatitudeOutOfBounds(val)) ||
        (mapping.targetField == CsvTargetField.longitude &&
            _isLongitudeOutOfBounds(val));
    if (!isInvalid) return null;
    return CsvRowError(
      rowIndex: rowIndex,
      csvHeader: mapping.csvHeader,
      targetField: mapping.targetField.dbValue,
      errorCode: 'invalid_coordinate',
      message: 'Coordenada geolocalizada fora dos limites permitidos.',
    );
  }

  static bool _isLatitudeOutOfBounds(num val) =>
      val < -90 || val > 90; // Physical Metric - Double Required
  static bool _isLongitudeOutOfBounds(num val) =>
      val < -180 || val > 180; // Physical Metric - Double Required

  CsvRowError? _validateDocument(
    String value,
    ColumnMapping mapping,
    int rowIndex,
    Map<String, int> documentTracker,
  ) {
    if (documentTracker.containsKey(value)) {
      final firstRow = documentTracker[value]!; // safe: containsKey guard above
      return CsvRowError(
        rowIndex: rowIndex,
        csvHeader: mapping.csvHeader,
        targetField: mapping.targetField.dbValue,
        errorCode: 'duplicate_in_batch',
        message:
            'Documento duplicado neste mesmo arquivo (visto na linha $firstRow).',
      );
    }
    documentTracker[value] = rowIndex;
    return null;
  }

  CsvRowError? _validateDate(
    String value,
    ColumnMapping mapping,
    int rowIndex,
  ) {
    if (DateTime.tryParse(value) == null && mapping.formatHint == null) {
      return CsvRowError(
        rowIndex: rowIndex,
        csvHeader: mapping.csvHeader,
        targetField: mapping.targetField.dbValue,
        errorCode: 'invalid_date',
        message:
            'Data inválida ou em formato não reconhecido (use padrão ISO-8601 ou especifique formato).',
      );
    }
    return null;
  }
}
