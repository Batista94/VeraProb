import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/app/routing/routing_utils.dart';

void main() {
  group('parseVehicleIdParam', () {
    test('returns valid UUID v4 unchanged', () {
      expect(
        parseVehicleIdParam('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
    });

    test('returns uppercase UUID (case-insensitive)', () {
      expect(
        parseVehicleIdParam('AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'),
        'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA',
      );
    });

    test('returns null for null input', () {
      expect(parseVehicleIdParam(null), isNull);
    });

    test('returns null for empty string', () {
      expect(parseVehicleIdParam(''), isNull);
    });

    test('returns null for literal "null" string', () {
      expect(parseVehicleIdParam('null'), isNull);
    });

    test('returns null for garbage input', () {
      expect(parseVehicleIdParam('not-a-uuid'), isNull);
    });

    test('returns null for SQL injection attempt', () {
      expect(parseVehicleIdParam("'; DROP TABLE vehicles; --"), isNull);
    });

    test('returns null for UUID missing hyphens', () {
      expect(parseVehicleIdParam('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'), isNull);
    });

    test('returns null for UUID with extra characters', () {
      expect(
        parseVehicleIdParam('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa-extra'),
        isNull,
      );
    });
  });
}
