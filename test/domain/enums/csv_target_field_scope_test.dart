// TDD RED — Bloco 1A: Entity Isolation
// Falha intencional até CsvTargetField.forEntity() ser implementado.
// Step 0: INV-7 (no dynamic), INV-14 (transport-agnostic fields).
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore

void main() {
  group('CsvTargetField.forEntity — Entity Isolation (Bloco 1A)', () {
    // ── asset ─────────────────────────────────────────────────────────────────

    test(
      'asset: contains identifier, assetModel, capacity, assetStatus, externalId, notes',
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
            CsvTargetField.notes,
          ]),
        );
      },
    );

    test(
      'asset: MUST NOT contain contractorDocument or latitude or longitude',
      () {
        final fields = CsvTargetField.forEntity('asset');
        expect(fields, isNot(contains(CsvTargetField.contractorDocument)));
        expect(fields, isNot(contains(CsvTargetField.latitude)));
        expect(fields, isNot(contains(CsvTargetField.longitude)));
      },
    );

    // ── operator ──────────────────────────────────────────────────────────────

    test(
      'operator: contains operatorName, operatorDocument, operatorLicense, operatorPhone',
      () {
        final fields = CsvTargetField.forEntity('operator');
        expect(
          fields,
          containsAll([
            CsvTargetField.operatorName,
            CsvTargetField.operatorDocument,
            CsvTargetField.operatorLicense,
            CsvTargetField.operatorPhone,
            CsvTargetField.externalId,
            CsvTargetField.notes,
          ]),
        );
      },
    );

    test('operator: MUST NOT contain latitude or contractCode', () {
      final fields = CsvTargetField.forEntity('operator');
      expect(fields, isNot(contains(CsvTargetField.latitude)));
      expect(fields, isNot(contains(CsvTargetField.contractCode)));
    });

    // ── contractor ────────────────────────────────────────────────────────────

    test('contractor: contains contractorDocument, externalId, notes', () {
      final fields = CsvTargetField.forEntity('contractor');
      expect(
        fields,
        containsAll([
          CsvTargetField.contractorDocument,
          CsvTargetField.externalId,
          CsvTargetField.notes,
        ]),
      );
    });

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
      'zone: contains zoneName, zoneCode, latitude, longitude, radiusMeters',
      () {
        final fields = CsvTargetField.forEntity('zone');
        expect(
          fields,
          containsAll([
            CsvTargetField.zoneName,
            CsvTargetField.zoneCode,
            CsvTargetField.latitude,
            CsvTargetField.longitude,
            CsvTargetField.radiusMeters,
            CsvTargetField.externalId,
            CsvTargetField.notes,
          ]),
        );
      },
    );

    test('zone: MUST NOT contain operatorDocument or capacity', () {
      final fields = CsvTargetField.forEntity('zone');
      expect(fields, isNot(contains(CsvTargetField.operatorDocument)));
      expect(fields, isNot(contains(CsvTargetField.capacity)));
    });

    // ── unknown entity fallback ───────────────────────────────────────────────

    test('unknown entity: returns all values (safe fallback)', () {
      final fields = CsvTargetField.forEntity('unknown_entity');
      expect(fields, equals(CsvTargetField.values));
    });
  });
}
