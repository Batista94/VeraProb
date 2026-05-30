// Unit tests for CsvTargetField enum.
//
// Validates the transport-agnostic field taxonomy (INV-14) and
// the dbValue contract used by ColumnMapping serialization.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';

void main() {
  group('CsvTargetField', () {
    // ── dbValue contract ──────────────────────────────────────────────────────

    test('dbValue equals name for all fields (stable DB column mapping)', () {
      for (final field in CsvTargetField.values) {
        expect(
          field.dbValue,
          equals(field.name),
          reason:
              'CsvTargetField.${field.name}.dbValue must equal its Dart name '
              'to ensure stable DB column mapping without migration.',
        );
      }
    });

    test('no dbValue is empty string (regression guard)', () {
      for (final field in CsvTargetField.values) {
        expect(
          field.dbValue.isNotEmpty,
          isTrue,
          reason: 'CsvTargetField.${field.name}.dbValue must not be empty.',
        );
      }
    });

    // ── Taxonomy coverage (INV-14 — transport-agnostic) ───────────────────────

    test('Asset group contains required fields (INV-14)', () {
      final assetFields = {
        CsvTargetField.identifier,
        CsvTargetField.assetModel,
        CsvTargetField.capacity,
        CsvTargetField.assetStatus,
      };
      for (final f in assetFields) {
        expect(
          CsvTargetField.values,
          contains(f),
          reason: 'Asset field $f required by INV-14 taxonomy.',
        );
      }
    });

    test('Operator group contains required fields (INV-14)', () {
      final operatorFields = {
        CsvTargetField.operatorName,
        CsvTargetField.operatorDocument,
        CsvTargetField.operatorLicense,
        CsvTargetField.operatorPhone,
      };
      for (final f in operatorFields) {
        expect(CsvTargetField.values, contains(f));
      }
    });

    test('Contract group contains required fields (INV-14)', () {
      final contractFields = {
        CsvTargetField.contractCode,
        CsvTargetField.contractorDocument,
        CsvTargetField.startDate,
        CsvTargetField.endDate,
      };
      for (final f in contractFields) {
        expect(CsvTargetField.values, contains(f));
      }
    });

    test('Zone group contains geofence fields (INV-14)', () {
      final zoneFields = {
        CsvTargetField.zoneName,
        CsvTargetField.zoneCode,
        CsvTargetField.latitude,
        CsvTargetField.longitude,
        CsvTargetField.radiusMeters,
        CsvTargetField.address,
      };
      for (final f in zoneFields) {
        expect(CsvTargetField.values, contains(f));
      }
    });

    test('Contractor group contains required fields (INV-14)', () {
      final contractorFields = {
        CsvTargetField.contractorName,
        CsvTargetField.contractorDocument,
        CsvTargetField.contractorEmail,
        CsvTargetField.contractorContactName,
      };
      for (final f in contractorFields) {
        expect(CsvTargetField.values, contains(f));
      }
    });

    test('Shared fields exist (externalId, notes)', () {
      expect(CsvTargetField.values, contains(CsvTargetField.externalId));
      expect(CsvTargetField.values, contains(CsvTargetField.notes));
    });

    // ── Regression guard ──

    test(
      'total field count matches taxonomy (23 fields — regression guard)',
      () {
        // If this fails after adding a new field, update the expected count
        // AND add the field to the appropriate taxonomy group test above.
        expect(
          CsvTargetField.values.length,
          equals(23),
          reason:
              'CsvTargetField field count changed. Update this test and '
              'ensure the new field is covered by a taxonomy group test.',
        );
      },
    );

    // ── Serialization round-trip ──────────────────────────────────────────────

    test('all fields parseable from dbValue via values lookup', () {
      for (final field in CsvTargetField.values) {
        final parsed = CsvTargetField.values.firstWhere(
          (f) => f.dbValue == field.dbValue,
        );
        expect(parsed, equals(field));
      }
    });
  });
}
