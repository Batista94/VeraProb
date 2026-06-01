import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/csv_preflight_validator.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';

// - [x] Update Implementation Plan with Emenda 1 and Emenda 2
// - [x] 1. Modelagem de Dados e Infraestrutura (SQL)
//   - [x] Create `csv_mapping_templates` table migration
// - [x] 2. Engenharia de Domínio e Aplicação (Dart)
//   - [x] Create `CsvTargetField` enum
//   - [x] Create `ColumnMapping` value object (with anti-injection)
//   - [x] Create `CsvMappingTemplate` entity
//   - [x] Create `ICsvMappingTemplateRepository` port
//   - [x] Implement Pre-flight validation logic (MIME sniffing, XSS, Partial Import)
// - [x] 3. Verification Plan & Testes (TDD / Cenários Adversos / Hacking)
//   - [x] Testes de Domínio e SecurityAssertionService (XSS, Formula Injection, MIME)
//   - [x] Testes de Validador de Pré-voo e limites de negócio
//   - [x] Testes de Application Handler e Isolamento de Tenant (INV-1, INV-22)

void main() {
  group('CsvPreflightValidator', () {
    late CsvPreflightValidator validator;
    late CsvMappingTemplate template;

    setUp(() {
      validator = CsvPreflightValidator();
      template = CsvMappingTemplate(
        id: '1',
        organizationId: 'org1',
        name: 'Test Template',
        targetEntity: 'asset',
        columnMappings: [
          const ColumnMapping(
            csvHeader: 'PLACA',
            targetField: CsvTargetField.identifier,
            required: true,
          ),
          const ColumnMapping(
            csvHeader: 'CAPACIDADE',
            targetField: CsvTargetField.capacity,
          ),
          const ColumnMapping(
            csvHeader: 'CNPJ',
            targetField: CsvTargetField.operatorDocument,
          ),
          const ColumnMapping(
            csvHeader: 'DATA',
            targetField: CsvTargetField.startDate,
          ),
          const ColumnMapping(
            csvHeader: 'LAT',
            targetField: CsvTargetField.latitude,
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
    });

    test('Validates clean CSV', () {
      final rows = [
        {
          'PLACA': 'ABC-1234',
          'CAPACIDADE': '40',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        },
        {
          'PLACA': 'DEF-5678',
          'CAPACIDADE': '42',
          'CNPJ': '11.444.777/0001-61',
          'DATA': '2024-01-02',
          'LAT': '-23.6',
        },
      ];

      final report = validator.validate(rows, template);

      expect(report.errors, isEmpty);
      expect(report.validRows, 2);
      expect(report.totalRows, 2);
    });

    // ── findUnmappedRequired (NOT-NULL coverage gate) ─────────────────────────

    CsvMappingTemplate contractorTemplate(List<ColumnMapping> mappings) =>
        CsvMappingTemplate(
          id: 'c',
          organizationId: 'org1',
          name: 'Contractors',
          targetEntity: 'contractor',
          columnMappings: mappings,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

    test('findUnmappedRequired flags the missing contractor name', () {
      // Repro of the CT01 bug: only externalId mapped, name/email/contact absent.
      final t = contractorTemplate(const [
        ColumnMapping(
          csvHeader: 'externalId',
          targetField: CsvTargetField.externalId,
        ),
      ]);

      final missing = validator.findUnmappedRequired(t);

      expect(
        missing,
        equals(const [
          CsvTargetField.contractorName,
          CsvTargetField.contractorEmail,
          CsvTargetField.contractorContactName,
        ]),
      );
    });

    test('findUnmappedRequired is empty when all required fields mapped', () {
      final t = contractorTemplate(const [
        ColumnMapping(
          csvHeader: 'contractorName',
          targetField: CsvTargetField.contractorName,
        ),
        ColumnMapping(
          csvHeader: 'contractorEmail',
          targetField: CsvTargetField.contractorEmail,
        ),
        ColumnMapping(
          csvHeader: 'contractorContactName',
          targetField: CsvTargetField.contractorContactName,
        ),
      ]);

      expect(validator.findUnmappedRequired(t), isEmpty);
    });

    test('Rejects missing required field', () {
      final rows = [
        {
          'PLACA': '   ',
          'CAPACIDADE': '40',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        },
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'required');
      expect(report.validRows, 0);
    });

    test('Rejects missing source header', () {
      final rows = [
        {
          'CAPACIDADE': '40',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        }, // PLACA is missing completely
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'missing_source');
    });

    test('Rejects non-numeric capacity', () {
      final rows = [
        {
          'PLACA': 'ABC-1234',
          'CAPACIDADE': 'quarenta',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        },
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'invalid_number');
    });

    test('Rejects out-of-bounds coordinate', () {
      final rows = [
        {
          'PLACA': 'ABC-1234',
          'CAPACIDADE': '40',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '91.5',
        },
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'invalid_coordinate');
    });

    test('Rejects duplicate CNPJ in batch', () {
      final rows = [
        {
          'PLACA': 'ABC-1234',
          'CAPACIDADE': '40',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        },
        {
          'PLACA': 'DEF-5678',
          'CAPACIDADE': '42',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-02',
          'LAT': '-23.6',
        }, // duplicate
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.length, 1);
      expect(report.errors.first.errorCode, 'duplicate_in_batch');
      expect(report.errors.first.rowIndex, 2);
      expect(report.validRows, 1); // Row 1 is valid, Row 2 is invalid
    });

    test('Hacking/Adverse: Rejects Formula Injection = in CSV payload', () {
      final rows = [
        {
          'PLACA': '=cmd|/C!',
          'CAPACIDADE': '40',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        },
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'injection_detected');
    });

    test('Hacking/Adverse: Rejects Formula Injection @ in CSV payload', () {
      final rows = [
        {
          'PLACA': '@SUM(1,1)',
          'CAPACIDADE': '40',
          'CNPJ': '11.222.333/0001-81',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        },
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'injection_detected');
    });

    test(
      'Hacking/Adverse: Processes but sanitizes HTML in payload (Stored XSS)',
      () {
        final rows = [
          {
            'PLACA': '<script>alert(1)</script>ABC-1234',
            'CAPACIDADE': '40',
            'CNPJ': '11.222.333/0001-81',
            'DATA': '2024-01-01',
            'LAT': '-23.5',
          },
        ];

        final report = validator.validate(rows, template);
        expect(report.isClean, true);
      },
    );

    // ── G1: mod-11 structural validation ──────────────────────────────────

    test('V2-new: Rejects CNPJ with invalid mod-11 check digit', () {
      final rows = [
        {
          'PLACA': 'ABC-1234',
          'CAPACIDADE': '40',
          'CNPJ': '12345678000199',
          'DATA': '2024-01-01',
          'LAT': '-23.5',
        },
      ];

      final report = validator.validate(rows, template);

      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'invalid_document');
      expect(report.errors.first.rowIndex, 1);
    });

    // ── G2: formatHint date parse ─────────────────────────────────────────

    test('V5-fix: Parses date with formatHint dd/MM/yyyy correctly', () {
      final templateWithHint = CsvMappingTemplate(
        id: '2',
        organizationId: 'org1',
        name: 'Date Hint Template',
        targetEntity: 'contract',
        columnMappings: [
          const ColumnMapping(
            csvHeader: 'DATA',
            targetField: CsvTargetField.startDate,
            formatHint: 'dd/MM/yyyy',
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final rows = [
        {'DATA': '25/12/2024'},
      ];

      final report = validator.validate(rows, templateWithHint);
      expect(report.isClean, true);
      expect(report.validRows, 1);
    });

    test('V5b: Rejects invalid date even with formatHint', () {
      final templateWithHint = CsvMappingTemplate(
        id: '3',
        organizationId: 'org1',
        name: 'Date Hint Template',
        targetEntity: 'contract',
        columnMappings: [
          const ColumnMapping(
            csvHeader: 'DATA',
            targetField: CsvTargetField.startDate,
            formatHint: 'dd/MM/yyyy',
          ),
        ],
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      final rows = [
        {'DATA': '99/99/9999'},
      ];

      final report = validator.validate(rows, templateWithHint);
      expect(report.hasErrors, true);
      expect(report.errors.first.errorCode, 'invalid_date');
      expect(report.errors.first.message, contains('dd/MM/yyyy'));
    });
  });
}
