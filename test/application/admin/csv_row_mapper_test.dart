// TDD RED — Bloco 1D: CSV row → DB-shaped map transformer.
// Step 0: INV-7 (typed coercion), INV-6 (dates normalised to UTC ISO-8601),
// INV-16 (output feeds a single batch RPC).
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/csv_row_mapper.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';

CsvMappingTemplate _tpl(String entity, List<ColumnMapping> mappings) =>
    CsvMappingTemplate(
      id: 't',
      organizationId: 'org-a',
      name: 'T',
      targetEntity: entity,
      columnMappings: mappings,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  const mapper = CsvRowMapper();

  group('CsvRowMapper (Bloco 1D)', () {
    test('asset: identifier→plate, capacity→int, status, externalId', () {
      final rows = mapper.toDbRows(
        targetEntity: 'asset',
        rows: const [
          {'PLACA': 'ABC-1234', 'CAP': '40', 'EXT': 'ERP-1'},
        ],
        template: _tpl('asset', const [
          ColumnMapping(
            csvHeader: 'PLACA',
            targetField: CsvTargetField.identifier,
          ),
          ColumnMapping(csvHeader: 'CAP', targetField: CsvTargetField.capacity),
          ColumnMapping(
            csvHeader: 'EXT',
            targetField: CsvTargetField.externalId,
          ),
        ]),
        resolvedContractors: const {},
      );

      expect(rows, hasLength(1));
      expect(rows.single['plate'], 'ABC-1234');
      expect(rows.single['capacity'], 40); // int, not '40'
      expect(rows.single['external_id'], 'ERP-1');
    });

    test('contractor: all four NOT NULL columns mapped', () {
      final rows = mapper.toDbRows(
        targetEntity: 'contractor',
        rows: const [
          {
            'NOME': 'ACME',
            'CNPJ': '11.222.333/0001-81',
            'EMAIL': 'a@b.com',
            'CONTATO': 'John',
          },
        ],
        template: _tpl('contractor', const [
          ColumnMapping(
            csvHeader: 'NOME',
            targetField: CsvTargetField.contractorName,
          ),
          ColumnMapping(
            csvHeader: 'CNPJ',
            targetField: CsvTargetField.contractorDocument,
          ),
          ColumnMapping(
            csvHeader: 'EMAIL',
            targetField: CsvTargetField.contractorEmail,
          ),
          ColumnMapping(
            csvHeader: 'CONTATO',
            targetField: CsvTargetField.contractorContactName,
          ),
        ]),
        resolvedContractors: const {},
      );

      expect(rows.single['name'], 'ACME');
      expect(rows.single['tax_id'], '11.222.333/0001-81');
      expect(rows.single['primary_email'], 'a@b.com');
      expect(rows.single['contact_name'], 'John');
    });

    test(
      'contract: contractCode→name, FK-resolved contractor_name, ISO dates',
      () {
        final resolved = {
          '11222333000181': Contractor(
            id: 'c1',
            organizationId: 'org-a',
            name: 'Resolved Contractor SA',
            taxId: '11222333000181',
            primaryEmail: 'a@b.com',
            contactName: 'John',
            createdAtUtc: DateTime.utc(2026, 1, 1),
          ),
        };

        final rows = mapper.toDbRows(
          targetEntity: 'contract',
          rows: const [
            {
              'COD': 'CT-1',
              'CNPJ': '11.222.333/0001-81',
              'INI': '01/03/2026',
              'FIM': '31/12/2026',
            },
          ],
          template: _tpl('contract', const [
            ColumnMapping(
              csvHeader: 'COD',
              targetField: CsvTargetField.contractCode,
            ),
            ColumnMapping(
              csvHeader: 'CNPJ',
              targetField: CsvTargetField.contractorDocument,
            ),
            ColumnMapping(
              csvHeader: 'INI',
              targetField: CsvTargetField.startDate,
              formatHint: 'dd/MM/yyyy',
            ),
            ColumnMapping(
              csvHeader: 'FIM',
              targetField: CsvTargetField.endDate,
              formatHint: 'dd/MM/yyyy',
            ),
          ]),
          resolvedContractors: resolved,
        );

        expect(rows.single['name'], 'CT-1');
        expect(rows.single['contractor_name'], 'Resolved Contractor SA');
        expect(rows.single['valid_from_utc'], '2026-03-01T00:00:00.000Z');
        expect(rows.single['valid_until_utc'], '2026-12-31T00:00:00.000Z');
      },
    );

    test('zone: lat/lng→double, radius→int, address', () {
      final rows = mapper.toDbRows(
        targetEntity: 'zone',
        rows: const [
          {
            'NOME': 'Garagem',
            'LAT': '-23.5',
            'LNG': '-46.6',
            'RAIO': '500',
            'END': 'Av. Paulista, 1000',
          },
        ],
        template: _tpl('zone', const [
          ColumnMapping(
            csvHeader: 'NOME',
            targetField: CsvTargetField.zoneName,
          ),
          ColumnMapping(csvHeader: 'LAT', targetField: CsvTargetField.latitude),
          ColumnMapping(
            csvHeader: 'LNG',
            targetField: CsvTargetField.longitude,
          ),
          ColumnMapping(
            csvHeader: 'RAIO',
            targetField: CsvTargetField.radiusMeters,
          ),
          ColumnMapping(
            csvHeader: 'END',
            targetField: CsvTargetField.address,
          ),
        ]),
        resolvedContractors: const {},
      );

      expect(rows.single['name'], 'Garagem');
      expect(rows.single['latitude'], -23.5);
      expect(rows.single['longitude'], -46.6);
      expect(rows.single['radius_meters'], 500);
      expect(rows.single['address'], 'Av. Paulista, 1000');
    });

    test('omits unmapped/empty external_id (NULL → fallback path)', () {
      final rows = mapper.toDbRows(
        targetEntity: 'asset',
        rows: const [
          {'PLACA': 'XYZ-0000', 'CAP': '10'},
        ],
        template: _tpl('asset', const [
          ColumnMapping(
            csvHeader: 'PLACA',
            targetField: CsvTargetField.identifier,
          ),
          ColumnMapping(csvHeader: 'CAP', targetField: CsvTargetField.capacity),
        ]),
        resolvedContractors: const {},
      );

      expect(rows.single.containsKey('external_id'), isFalse);
    });
  });
}
