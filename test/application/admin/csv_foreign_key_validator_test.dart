// TDD RED — Bloco 1C: FK Pre-flight (async).
// Step 0: INV-22 / INV-26 (anti-oracle: cross-tenant FK hit is indistinguishable
// from a genuine miss), INV-16 (single batch lookup), INV-10 (typed errors).
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/csv_foreign_key_validator.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';

/// In-memory contractor repo. Honours tenant scope on [findByTaxIds]:
/// only contractors owned by [organizationId] with a digit-normalised tax_id
/// in the requested set are returned (anti-oracle — cross-tenant rows are
/// simply absent, never surfaced).
class _FakeContractorRepository implements ContractorRepository {
  _FakeContractorRepository(this._seed);
  final List<Contractor> _seed;

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  @override
  Future<Map<String, Contractor>> findByTaxIds(
    String organizationId,
    Set<String> taxIds,
  ) async {
    final wanted = taxIds.map(_digits).toSet();
    final result = <String, Contractor>{};
    for (final c in _seed) {
      if (c.organizationId != organizationId) continue;
      final d = _digits(c.taxId ?? '');
      if (wanted.contains(d)) result[d] = c;
    }
    return result;
  }

  @override
  Future<List<Contractor>> findByOrganization(String organizationId) async =>
      _seed.where((c) => c.organizationId == organizationId).toList();

  @override
  Future<Contractor?> findById(String organizationId, String id) async => null;

  @override
  Future<void> save(Contractor contractor) async {}

  @override
  Future<void> delete(String organizationId, String id) async {}

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async => rows.length;
}

CsvMappingTemplate _contractTemplate() => CsvMappingTemplate(
  id: 't1',
  organizationId: 'org-a',
  name: 'Contracts',
  targetEntity: 'contract',
  columnMappings: const [
    ColumnMapping(
      csvHeader: 'CODIGO',
      targetField: CsvTargetField.contractCode,
    ),
    ColumnMapping(
      csvHeader: 'CNPJ',
      targetField: CsvTargetField.contractorDocument,
    ),
  ],
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Contractor _contractor(String org, String taxId) => Contractor(
  id: 'c-$org-$taxId',
  organizationId: org,
  name: 'ACME $taxId',
  taxId: taxId,
  primaryEmail: 'a@b.com',
  contactName: 'John',
  createdAtUtc: DateTime.utc(2026, 1, 1),
);

void main() {
  group('CsvForeignKeyValidator (Bloco 1C)', () {
    const ownedCnpj = '11.222.333/0001-81';
    const ownedDigits = '11222333000181';
    const absentCnpj = '99888777000166';

    test('a: contractor CNPJ owned by org → no FK error, resolved upward', () async {
      final validator = CsvForeignKeyValidator(
        contractorRepo: _FakeContractorRepository([
          _contractor('org-a', ownedCnpj),
        ]),
      );

      final result = await validator.validate(
        organizationId: 'org-a',
        targetEntity: 'contract',
        rows: const [
          {'CODIGO': 'CT-1', 'CNPJ': ownedCnpj},
        ],
        template: _contractTemplate(),
      );

      expect(result.errors, isEmpty);
      expect(result.resolvedContractors[ownedDigits]?.organizationId, 'org-a');
    });

    test('b: CNPJ absent in tenant → foreign_key_not_found', () async {
      final validator = CsvForeignKeyValidator(
        contractorRepo: _FakeContractorRepository([
          _contractor('org-a', ownedCnpj),
        ]),
      );

      final result = await validator.validate(
        organizationId: 'org-a',
        targetEntity: 'contract',
        rows: const [
          {'CODIGO': 'CT-1', 'CNPJ': absentCnpj},
        ],
        template: _contractTemplate(),
      );

      expect(result.errors, hasLength(1));
      expect(result.errors.single.errorCode, 'foreign_key_not_found');
      expect(result.errors.single.rowIndex, 1);
      expect(result.errors.single.targetField, 'contractor_document');
    });

    test(
      'c: cross-tenant CNPJ → byte-identical foreign_key_not_found (anti-oracle, INV-26)',
      () async {
        // Same CNPJ exists, but belongs to org-b. org-a must NOT learn it exists.
        final crossTenantRepo = _FakeContractorRepository([
          _contractor('org-b', ownedCnpj),
        ]);
        final missRepo = _FakeContractorRepository([]);

        final validatorCross = CsvForeignKeyValidator(
          contractorRepo: crossTenantRepo,
        );
        final validatorMiss = CsvForeignKeyValidator(contractorRepo: missRepo);

        final rows = [
          {'CODIGO': 'CT-1', 'CNPJ': ownedCnpj},
        ];

        final crossResult = await validatorCross.validate(
          organizationId: 'org-a',
          targetEntity: 'contract',
          rows: rows,
          template: _contractTemplate(),
        );
        final missResult = await validatorMiss.validate(
          organizationId: 'org-a',
          targetEntity: 'contract',
          rows: rows,
          template: _contractTemplate(),
        );

        expect(crossResult.errors, hasLength(1));
        expect(crossResult.errors.single.errorCode, 'foreign_key_not_found');
        // Identical message + code: zero oracle signal distinguishing the two.
        expect(
          crossResult.errors.single.message,
          equals(missResult.errors.single.message),
        );
        expect(crossResult.resolvedContractors, isEmpty);
      },
    );

    test('d: mixed batch flags only the invalid rows', () async {
      final validator = CsvForeignKeyValidator(
        contractorRepo: _FakeContractorRepository([
          _contractor('org-a', ownedCnpj),
        ]),
      );

      final result = await validator.validate(
        organizationId: 'org-a',
        targetEntity: 'contract',
        rows: const [
          {'CODIGO': 'CT-1', 'CNPJ': ownedCnpj},
          {'CODIGO': 'CT-2', 'CNPJ': absentCnpj},
          {'CODIGO': 'CT-3', 'CNPJ': ownedCnpj},
        ],
        template: _contractTemplate(),
      );

      expect(result.errors, hasLength(1));
      expect(result.errors.single.rowIndex, 2);
    });

    test('e: non-contract entity → no FK checks (framework no-op)', () async {
      final validator = CsvForeignKeyValidator(
        contractorRepo: _FakeContractorRepository([]),
      );

      final result = await validator.validate(
        organizationId: 'org-a',
        targetEntity: 'asset',
        rows: const [
          {'PLACA': 'ABC-1234'},
        ],
        template: CsvMappingTemplate(
          id: 't2',
          organizationId: 'org-a',
          name: 'Assets',
          targetEntity: 'asset',
          columnMappings: const [
            ColumnMapping(
              csvHeader: 'PLACA',
              targetField: CsvTargetField.identifier,
            ),
          ],
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(result.errors, isEmpty);
      expect(result.resolvedContractors, isEmpty);
    });
  });
}
