import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Persistent CSV mapping template scoped to an organization (INV-1).
///
/// Stores the de-para (source → target) configuration so the user
/// doesn't have to re-map columns on every import.
class CsvMappingTemplate extends Equatable {
  final String id;
  final String organizationId;
  final String name;
  final String targetEntity; // 'asset' | 'contract' | 'zone' | 'operator'
  final List<ColumnMapping> columnMappings;
  final bool isDefault;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  const CsvMappingTemplate({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.targetEntity,
    required this.columnMappings,
    this.isDefault = false,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  /// Validates structural integrity (INV-10).
  /// Call after deserialization or before persistence.
  void assertValid() {
    if (name.trim().isEmpty) {
      throw const IntegrityException(
        'Template name cannot be empty',
        field: 'name',
      );
    }

    // Security: HTML Stripping on template name to prevent Stored XSS
    if (name.contains(RegExp(r'<[^>]*>'))) {
      throw const IntegrityException(
        'Template name contains invalid characters',
        field: 'name',
      );
    }

    if (columnMappings.isEmpty) {
      throw const IntegrityException(
        'At least one column mapping is required',
        field: 'columnMappings',
      );
    }

    // Detect duplicate target field assignments
    final targets = <String>{};
    for (final m in columnMappings) {
      if (!targets.add(m.targetField.dbValue)) {
        throw IntegrityException(
          'Duplicate target field: ${m.targetField.dbValue}',
          field: 'columnMappings',
        );
      }
    }
  }

  CsvMappingTemplate copyWith({
    String? name,
    String? targetEntity,
    List<ColumnMapping>? columnMappings,
    bool? isDefault,
    int? version,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return CsvMappingTemplate(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      targetEntity: targetEntity ?? this.targetEntity,
      columnMappings: columnMappings ?? this.columnMappings,
      isDefault: isDefault ?? this.isDefault,
      version: version ?? this.version,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    name,
    targetEntity,
    columnMappings,
    isDefault,
    version,
  ];
}
