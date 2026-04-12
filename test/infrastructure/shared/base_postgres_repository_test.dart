import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Test harness that exposes the static methods of [BasePostgresRepository].
///
/// Since `_sortKeys` and `_hashPayloadIfPresent` are private static methods,
/// we use the public `@visibleForTesting` wrappers:
/// `BasePostgresRepository.hashPayload()`, `sortKeys()`, and `canonicalJson()`.
void main() {
  group('BasePostgresRepository._sortKeys', () {
    test(
      'produces deterministic hash for same payload with different key order',
      () {
        // Two maps with same data but different insertion order
        final payloadA = <String, dynamic>{
          'zebra': 1,
          'alpha': 2,
          'middle': {'z': 'zulu', 'a': 'alpha'},
        };
        final payloadB = <String, dynamic>{
          'middle': {'a': 'alpha', 'z': 'zulu'},
          'alpha': 2,
          'zebra': 1,
        };

        final hashA = BasePostgresRepository.hashPayload(payloadA);
        final hashB = BasePostgresRepository.hashPayload(payloadB);

        expect(hashA, isNotNull);
        expect(hashB, isNotNull);
        expect(
          hashA,
          equals(hashB),
          reason: 'Same logical payload must produce identical hashes',
        );
      },
    );

    test('normalizes DateTime to ISO-8601 string with Z suffix', () {
      final dt = DateTime.utc(2026, 4, 11, 15, 30, 0);
      final payload = <String, dynamic>{'timestamp': dt, 'name': 'test'};

      final hash = BasePostgresRepository.hashPayload(payload);
      expect(hash, isNotNull);

      // Verify the DateTime was normalized by checking the canonical JSON
      // contains the expected ISO-8601 format
      final canonicalJson = BasePostgresRepository.canonicalJson(payload);
      expect(canonicalJson, contains('2026-04-11T15:30:00'));
      expect(
        canonicalJson,
        contains('Z'),
        reason: 'DateTime must end with Z for UTC parity with Deno',
      );
    });

    test('normalizes DateTime nested inside a list', () {
      final payload = <String, dynamic>{
        'events': [
          {'z_time': DateTime.utc(2026, 1, 1, 0, 0, 0), 'a_field': 'first'},
          {'z_time': DateTime.utc(2026, 1, 2, 12, 0, 0), 'a_field': 'second'},
        ],
        'meta': 'test',
      };

      final hash = BasePostgresRepository.hashPayload(payload);
      expect(hash, isNotNull);

      final canonicalJson = BasePostgresRepository.canonicalJson(payload);
      // Verify DateTime inside list elements was normalized
      expect(canonicalJson, contains('2026-01-01T00:00:00.000Z'));
      expect(canonicalJson, contains('2026-01-02T12:00:00.000Z'));
    });

    test('sorts keys inside maps nested within lists', () {
      final payload = <String, dynamic>{
        'items': [
          {'z': 1, 'a': 2, 'm': 3},
          {'z': 10, 'a': 20},
        ],
      };

      final canonicalJson = BasePostgresRepository.canonicalJson(payload);
      // After canonicalization, keys inside list elements must be sorted:
      // {"a":2,"m":3,"z":1} not {"z":1,"a":2,"m":3}
      final decoded = jsonDecode(canonicalJson) as Map<String, dynamic>;
      final items = decoded['items'] as List<dynamic>;

      final firstItem = items[0] as Map<String, dynamic>;
      expect(firstItem.keys.toList(), equals(['a', 'm', 'z']));

      final secondItem = items[1] as Map<String, dynamic>;
      expect(secondItem.keys.toList(), equals(['a', 'z']));
    });

    test(
      'handles deeply nested structures (map > list > map > list > map)',
      () {
        final payload = <String, dynamic>{
          'z_top': {
            'nested_list': [
              {
                'deep_map': [
                  {'z_deepest': 'end', 'a_deepest': 'start'},
                ],
              },
            ],
          },
          'a_top': 42,
        };

        final canonicalJson = BasePostgresRepository.canonicalJson(payload);
        final decoded = jsonDecode(canonicalJson) as Map<String, dynamic>;

        // Top-level keys must be sorted
        expect(decoded.keys.toList(), equals(['a_top', 'z_top']));

        // Deepest map keys must be sorted
        final zTop = decoded['z_top'] as Map<String, dynamic>;
        final nestedList = zTop['nested_list'] as List<dynamic>;
        final nestedMap = nestedList[0] as Map<String, dynamic>;
        final deepList = nestedMap['deep_map'] as List<dynamic>;
        final deepestMap = deepList[0] as Map<String, dynamic>;
        expect(deepestMap.keys.toList(), equals(['a_deepest', 'z_deepest']));
      },
    );

    test('returns null for null payload', () {
      final hash = BasePostgresRepository.hashPayload(null);
      expect(hash, isNull);
    });

    test('returns null for empty payload', () {
      final hash = BasePostgresRepository.hashPayload(<String, dynamic>{});
      expect(hash, isNull);
    });

    test('handles primitives inside maps without modification', () {
      final payload = <String, dynamic>{
        'z_string': 'hello',
        'a_int': 42,
        'm_double': 3.14,
        'b_bool': true,
        'n_null': null,
      };

      final hash = BasePostgresRepository.hashPayload(payload);
      expect(hash, isNotNull);

      final canonicalJson = BasePostgresRepository.canonicalJson(payload);
      // Keys must be sorted alphabetically
      expect(canonicalJson, startsWith('{"a_int":42'));
    });

    test('handles empty lists and empty maps within payload', () {
      final payload = <String, dynamic>{
        'z_empty_list': <dynamic>[],
        'a_empty_map': <String, dynamic>{},
        'data': 1,
      };

      final hash = BasePostgresRepository.hashPayload(payload);
      expect(hash, isNotNull);
    });

    test('handles list of primitives', () {
      final payload = <String, dynamic>{
        'tags': ['z', 'a', 'm'],
        'counts': [3, 1, 2],
      };

      final canonicalJson = BasePostgresRepository.canonicalJson(payload);
      final decoded = jsonDecode(canonicalJson) as Map<String, dynamic>;
      // List elements are NOT sorted (they preserve order) — only map keys are sorted
      expect(decoded['tags'], equals(['z', 'a', 'm']));
      expect(decoded['counts'], equals([3, 1, 2]));
    });

    test('DateTime with local timezone is converted to UTC', () {
      // Create a DateTime in local timezone
      final localDt = DateTime(2026, 4, 11, 15, 30, 0); // no .utc
      final payload = <String, dynamic>{'event_time': localDt};

      final canonicalJson = BasePostgresRepository.canonicalJson(payload);

      // Should contain UTC-normalized timestamp
      final decoded = jsonDecode(canonicalJson) as Map<String, dynamic>;
      final parsed = DateTime.parse(decoded['event_time'] as String);
      expect(
        parsed.isUtc,
        isTrue,
        reason: 'Local DateTime must be converted to UTC before hashing',
      );
    });

    test('sortKeys returns primitives unchanged', () {
      expect(BasePostgresRepository.sortKeys(null), isNull);
      expect(BasePostgresRepository.sortKeys(42), 42);
      expect(BasePostgresRepository.sortKeys('hello'), 'hello');
      expect(BasePostgresRepository.sortKeys(true), isTrue);
      expect(BasePostgresRepository.sortKeys(3.14), 3.14);
    });

    test('sortKeys sorts a simple map', () {
      final input = <String, dynamic>{'z': 1, 'a': 2, 'm': 3};
      final result =
          BasePostgresRepository.sortKeys(input) as Map<String, dynamic>;
      expect(result.keys.toList(), equals(['a', 'm', 'z']));
    });

    test('sortKeys handles a list at the top level', () {
      final input = <String, dynamic>{
        'items': [
          {'z': 1, 'a': 2},
          {'m': 3, 'b': 4},
        ],
      };
      final result =
          BasePostgresRepository.sortKeys(input) as Map<String, dynamic>;
      final items = result['items'] as List<dynamic>;
      expect(
        (items[0] as Map<String, dynamic>).keys.toList(),
        equals(['a', 'z']),
      );
      expect(
        (items[1] as Map<String, dynamic>).keys.toList(),
        equals(['b', 'm']),
      );
    });
  });

  group('BasePostgresRepository._hashPayloadIfPresent', () {
    test('produces same hash for logically equivalent nested payloads', () {
      final payloadA = <String, dynamic>{
        'organization_id': 'org-123',
        'events': [
          {
            'timestamp': DateTime.utc(2026, 4, 11),
            'type': 'check_in',
            'metadata': {'z': 'last', 'a': 'first'},
          },
        ],
        'device_id': 'dev-456',
      };

      final payloadB = <String, dynamic>{
        'device_id': 'dev-456',
        'organization_id': 'org-123',
        'events': [
          {
            'metadata': {'a': 'first', 'z': 'last'},
            'type': 'check_in',
            'timestamp': DateTime.utc(2026, 4, 11),
          },
        ],
      };

      final hashA = BasePostgresRepository.hashPayload(payloadA);
      final hashB = BasePostgresRepository.hashPayload(payloadB);

      expect(
        hashA,
        equals(hashB),
        reason:
            'Different insertion order + nested key order must still produce identical hash',
      );
    });

    test('produces different hash for different values', () {
      final payloadA = <String, dynamic>{'id': 'abc', 'value': 1};
      final payloadB = <String, dynamic>{'id': 'abc', 'value': 2};

      final hashA = BasePostgresRepository.hashPayload(payloadA);
      final hashB = BasePostgresRepository.hashPayload(payloadB);

      expect(hashA, isNot(equals(hashB)));
    });

    test('hash is valid SHA-256 hex format (64 chars)', () {
      final payload = <String, dynamic>{'test': true};
      final hash = BasePostgresRepository.hashPayload(payload);

      expect(hash, isNotNull);
      expect(hash!.length, equals(64));
      // Valid hex chars only
      expect(hash, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('Dart canonical JSON matches Deno sortKeys output for identical payload', () {
      // This test proves that the Dart _sortKeys output, when JSON-encoded,
      // would produce the same string as Deno's sortKeys + JSON.stringify.
      //
      // The Deno equivalent:
      //   JSON.stringify(sortKeys({device_id:"dev-456",events:[{ts:new Date("2026-04-11T00:00:00Z"),type:"check_in"}],organization_id:"org-123"}))
      //
      // Expected Deno output (keys sorted, DateTime as ISO string):
      //   {"device_id":"dev-456","events":[{"ts":"2026-04-11T00:00:00.000Z","type":"check_in"}],"organization_id":"org-123"}

      final payload = <String, dynamic>{
        'organization_id': 'org-123',
        'device_id': 'dev-456',
        'events': [
          {'type': 'check_in', 'ts': DateTime.utc(2026, 4, 11, 0, 0, 0)},
        ],
      };

      final canonicalJson = BasePostgresRepository.canonicalJson(payload);

      // Expected: keys sorted at every level, DateTime normalized to ISO-8601 Z
      const expectedDenoEquivalent =
          '{"device_id":"dev-456","events":[{"ts":"2026-04-11T00:00:00.000Z","type":"check_in"}],"organization_id":"org-123"}';

      expect(
        canonicalJson,
        equals(expectedDenoEquivalent),
        reason:
            'Dart canonical JSON must be byte-identical to Deno sortKeys output',
      );
    });
  });
}
