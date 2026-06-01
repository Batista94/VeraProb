// TDD RED — Bloco 1A: Entity Isolation
// Falha intencional até CsvTargetField.forEntity() ser implementado.
// Step 0: INV-7 (no dynamic), INV-14 (transport-agnostic fields).
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore

void main() {
  group('CsvTargetField.forEntity — Entity Isolation (Bloco 1A)', () {
    // ── asset ─────────────────────────────────────────────────────────────────

    test(
      'asset: contains identifier, assetModel, capacity, assetStatus, externalId',
      () {
        final fields = CsvTargetField.forEntity('asset');
        expect(
          fields,
          containsAll([
            CsvTargetField.identifier,
            CsvTargetField.assetModel,
            CsvTargetField.capacity,
            CsvTargetField.assetStatus,
            CsvTargetField.externalId,
          ]),
        );
      },
    );

    test(
      'asset: MUST NOT contain contractorDocument, latitude, longitude or notes',
      () {
        final fields = CsvTargetField.forEntity('asset');
        expect(fields, isNot(contains(CsvTargetField.contractorDocument)));
        expect(fields, isNot(contains(CsvTargetField.latitude)));
        expect(fields, isNot(contains(CsvTargetField.longitude)));
        // notes has no backing column on assets — must not be offered.
        expect(fields, isNot(contains(CsvTargetField.notes)));
      },
    );

    // ── operator ──────────────────────────────────────────────────────────────

    test(
      'operator: contains name, document(CPF), license(+category,expiry), phone',
      () {
        final fields = CsvTargetField.forEntity('operator');
        expect(
          fields,
          containsAll([
            CsvTargetField.operatorName,
            CsvTargetField.operatorDocument,
            CsvTargetField.operatorLicense,
            CsvTargetField.operatorLicenseCategory,
            CsvTargetField.operatorLicenseExpiry,
            CsvTargetField.operatorPhone,
            CsvTargetField.externalId,
          ]),
        );
      },
    );

    test('operator: MUST NOT contain latitude, contractCode or notes', () {
      final fields = CsvTargetField.forEntity('operator');
      expect(fields, isNot(contains(CsvTargetField.latitude)));
      expect(fields, isNot(contains(CsvTargetField.contractCode)));
      expect(fields, isNot(contains(CsvTargetField.notes)));
    });

    test(
      'operator: MUST NOT contain contractor-specific fields (scope isolation)',
      () {
        final fields = CsvTargetField.forEntity('operator');
        expect(fields, isNot(contains(CsvTargetField.contractorName)));
        expect(fields, isNot(contains(CsvTargetField.contractorEmail)));
        expect(fields, isNot(contains(CsvTargetField.contractorContactName)));
      },
    );

    // ── contractor ────────────────────────────────────────────────────────────

    test('contractor: contains contractorDocument, externalId', () {
      final fields = CsvTargetField.forEntity('contractor');
      expect(
        fields,
        containsAll([
          CsvTargetField.contractorDocument,
          CsvTargetField.externalId,
        ]),
      );
      // notes has no backing column on contractors — must not be offered.
      expect(fields, isNot(contains(CsvTargetField.notes)));
    });

    test(
      'contractor: contains contractorName, contractorEmail, contractorContactName '
      '(Bloco 1C.0 — NOT NULL columns coverable)',
      () {
        final fields = CsvTargetField.forEntity('contractor');
        expect(
          fields,
          containsAll([
            CsvTargetField.contractorName,
            CsvTargetField.contractorEmail,
            CsvTargetField.contractorContactName,
          ]),
        );
      },
    );

    test(
      'contractor: MUST NOT contain latitude (INV-22 oracle prevention)',
      () {
        final fields = CsvTargetField.forEntity('contractor');
        expect(fields, isNot(contains(CsvTargetField.latitude)));
        expect(fields, isNot(contains(CsvTargetField.longitude)));
        expect(fields, isNot(contains(CsvTargetField.identifier)));
      },
    );

    // ── contract ──────────────────────────────────────────────────────────────

    test(
      'contract: contains contractCode, contractorDocument, startDate, endDate',
      () {
        final fields = CsvTargetField.forEntity('contract');
        expect(
          fields,
          containsAll([
            CsvTargetField.contractCode,
            CsvTargetField.contractorDocument,
            CsvTargetField.startDate,
            CsvTargetField.endDate,
            CsvTargetField.externalId,
            CsvTargetField.notes,
          ]),
        );
      },
    );

    test('contract: MUST NOT contain assetModel or latitude', () {
      final fields = CsvTargetField.forEntity('contract');
      expect(fields, isNot(contains(CsvTargetField.assetModel)));
      expect(fields, isNot(contains(CsvTargetField.latitude)));
    });

    // ── zone ──────────────────────────────────────────────────────────────────

    test(
      'zone: contains zoneName, latitude, longitude, radiusMeters, address',
      () {
        final fields = CsvTargetField.forEntity('zone');
        expect(
          fields,
          containsAll([
            CsvTargetField.zoneName,
            CsvTargetField.latitude,
            CsvTargetField.longitude,
            CsvTargetField.radiusMeters,
            CsvTargetField.address,
            CsvTargetField.externalId,
          ]),
        );
      },
    );

    test(
      'zone: MUST NOT contain operatorDocument, capacity, zoneCode or notes',
      () {
        final fields = CsvTargetField.forEntity('zone');
        expect(fields, isNot(contains(CsvTargetField.operatorDocument)));
        expect(fields, isNot(contains(CsvTargetField.capacity)));
        // zoneCode is redundant with externalId; notes has no column — neither offered.
        expect(fields, isNot(contains(CsvTargetField.zoneCode)));
        expect(fields, isNot(contains(CsvTargetField.notes)));
      },
    );

    // ── unknown entity fallback ───────────────────────────────────────────────

    test('unknown entity: returns all values (safe fallback)', () {
      final fields = CsvTargetField.forEntity('unknown_entity');
      expect(fields, equals(CsvTargetField.values));
    });
  });
}
