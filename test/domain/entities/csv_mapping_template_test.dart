import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  group('CsvMappingTemplate', () {
    final validMappings = [
      const ColumnMapping(
        csvHeader: 'PLACA',
        targetField: CsvTargetField.identifier,
      ),
      const ColumnMapping(
        csvHeader: 'CAPACIDADE',
        targetField: CsvTargetField.capacity,
      ),
    ];

    test('assertValid - Happy path', () {
      final template = CsvMappingTemplate(
        id: '1',
        organizationId: 'org1',
        name: 'Template Frota',
        targetEntity: 'asset',
        columnMappings: validMappings,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(() => template.assertValid(), returnsNormally);
    });

    test('assertValid - Rejects empty name', () {
      final template = CsvMappingTemplate(
        id: '1',
        organizationId: 'org1',
        name: '   ',
        targetEntity: 'asset',
        columnMappings: validMappings,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(
        () => template.assertValid(),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            contains('Template name cannot be empty'),
          ),
        ),
      );
    });

    test('assertValid - Rejects empty column mappings', () {
      final template = CsvMappingTemplate(
        id: '1',
        organizationId: 'org1',
        name: 'Template Frota',
        targetEntity: 'asset',
        columnMappings: const [],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(
        () => template.assertValid(),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            contains('At least one column mapping is required'),
          ),
        ),
      );
    });

    test('assertValid - Rejects duplicate target fields', () {
      final mappings = [
        const ColumnMapping(
          csvHeader: 'PLACA1',
          targetField: CsvTargetField.identifier,
        ),
        const ColumnMapping(
          csvHeader: 'PLACA2',
          targetField: CsvTargetField.identifier,
        ),
      ];

      final template = CsvMappingTemplate(
        id: '1',
        organizationId: 'org1',
        name: 'Template Frota',
        targetEntity: 'asset',
        columnMappings: mappings,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(
        () => template.assertValid(),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            contains('Duplicate target field'),
          ),
        ),
      );
    });

    test('assertValid - Hacking/Adverse: Rejects Stored XSS in name', () {
      final template = CsvMappingTemplate(
        id: '1',
        organizationId: 'org1',
        name: 'Template <script>alert(1)</script>',
        targetEntity: 'asset',
        columnMappings: validMappings,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      expect(
        () => template.assertValid(),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            contains('invalid characters'),
          ),
        ),
      );
    });
  });
}
