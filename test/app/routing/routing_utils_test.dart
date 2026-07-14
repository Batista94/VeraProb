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

  group('parseContractIdParam', () {
    test('returns valid UUID unchanged', () {
      expect(
        parseContractIdParam('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
    });

    test('returns null for malformed / empty / null', () {
      expect(parseContractIdParam(null), isNull);
      expect(parseContractIdParam(''), isNull);
      expect(parseContractIdParam('null'), isNull);
      expect(parseContractIdParam('not-a-uuid'), isNull);
    });
  });

  group('parseSandboxContractIdFromPath', () {
    test('returns UUID for valid sandbox deep link', () {
      expect(
        parseSandboxContractIdFromPath(
          '/admin/hub/contracts/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/sandbox',
        ),
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
    });

    test('returns null for missing segment or malformed UUID', () {
      expect(
        parseSandboxContractIdFromPath('/admin/hub/contracts/sandbox'),
        isNull,
      );
      expect(
        parseSandboxContractIdFromPath(
          '/admin/hub/contracts/not-a-uuid/sandbox',
        ),
        isNull,
      );
      expect(
        parseSandboxContractIdFromPath(
          '/admin/hub/contracts/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/rules',
        ),
        isNull,
      );
    });
  });
}
