// pr_scanner: ignore-regression — INV-7+INV-10+INV-14 value object, Council-reviewed
import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/security_assertion_service.dart';

/// Represents a single CSV-header → VeraProb-field mapping.
/// Immutable value object (INV-7: no dynamic).
class ColumnMapping extends Equatable {
  final String csvHeader;
  final CsvTargetField targetField;
  final String? transform;
  final bool required;
  final String? formatHint;

  const ColumnMapping({
    required this.csvHeader,
    required this.targetField,
    this.transform,
    this.required = false,
    this.formatHint,
  });

  /// Factory with IntegrityException shield (INV-10).
  factory ColumnMapping.fromJson(Map<String, Object?> json) {
    final csvHeader = json['csv_header'] as String?;
    if (csvHeader == null || csvHeader.isEmpty) {
      throw const IntegrityException(
        'csv_header is required',
        field: 'csv_header',
      );
    }

    // Security: Basic sanitization of header names to prevent DB/JSON anomalies
    // XSS and CSV Injection validations occur on the data rows, but header names
    // should also be clean.
    final cleanHeader = SecurityAssertionService.sanitizeHtml(csvHeader);

    if (cleanHeader.isEmpty) {
      throw const IntegrityException(
        'csv_header is required and cannot be empty after sanitization',
        field: 'csv_header',
      );
    }

    return ColumnMapping(
      csvHeader: cleanHeader,
      targetField: IntegrityException.shield(
        CsvTargetField.values,
        json['target_field'] as String? ?? '',
        'target_field',
      ),
      transform: json['transform'] as String?,
      required: json['required'] as bool? ?? false,
      formatHint: json['format_hint'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'csv_header': csvHeader,
    'target_field': targetField.dbValue,
    'transform': transform,
    'required': required,
    'format_hint': formatHint,
  };

  @override
  List<Object?> get props => [
    csvHeader,
    targetField,
    transform,
    required,
    formatHint,
  ];
}
