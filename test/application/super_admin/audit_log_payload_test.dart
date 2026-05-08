import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/audit_log_payload.dart';

void main() {
  group('AuditLogPayload', () {
    group('constructor defaults', () {
      test('creates empty payload with no arguments', () {
        const payload = AuditLogPayload();
        expect(payload.before, isEmpty);
        expect(payload.after, isEmpty);
        expect(payload.context, isEmpty);
      });

      test('accepts explicit maps', () {
        final payload = AuditLogPayload(
          before: {'key': 'old'},
          after: {'key': 'new'},
          context: {'user': 'admin'},
        );
        expect(payload.before, {'key': 'old'});
        expect(payload.after, {'key': 'new'});
        expect(payload.context, {'user': 'admin'});
      });
    });

    group('fromRaw', () {
      test('returns empty payload for null input', () {
        final payload = AuditLogPayload.fromRaw(null);
        expect(payload.isEmpty, isTrue);
        expect(payload.before, isEmpty);
        expect(payload.after, isEmpty);
        expect(payload.context, isEmpty);
      });

      test('returns empty payload for empty map input', () {
        final payload = AuditLogPayload.fromRaw({});
        expect(payload.isEmpty, isTrue);
      });

      test('parses valid before/after/context maps', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {'status': 'active', 'role': 'operator'},
          'after': {'status': 'suspended', 'role': 'operator'},
          'context': {'reason': 'policy_violation', 'actor': 'admin_01'},
        });
        expect(payload.before['status'], 'active');
        expect(payload.after['status'], 'suspended');
        expect(payload.context['reason'], 'policy_violation');
      });

      test('handles missing before key gracefully', () {
        final payload = AuditLogPayload.fromRaw({
          'after': {'x': 1},
          'context': {'y': 2},
        });
        expect(payload.before, isEmpty);
        expect(payload.after, {'x': 1});
        expect(payload.context, {'y': 2});
      });

      test('handles missing after key gracefully', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {'x': 1},
        });
        expect(payload.after, isEmpty);
        expect(payload.before, {'x': 1});
      });

      test('handles missing context key gracefully', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {'a': 1},
          'after': {'a': 2},
        });
        expect(payload.context, isEmpty);
      });

      // --- ADVERSARIAL: Non-map values for before/after/context ---
      test('treats non-map before value as empty map', () {
        final payload = AuditLogPayload.fromRaw({
          'before': 'not a map',
          'after': {'key': 'value'},
        });
        expect(payload.before, isEmpty);
        expect(payload.after, {'key': 'value'});
      });

      test('treats non-map after value as empty map', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {'key': 'value'},
          'after': 42,
        });
        expect(payload.after, isEmpty);
        expect(payload.before, {'key': 'value'});
      });

      test('treats non-map context value as empty map', () {
        final payload = AuditLogPayload.fromRaw({
          'context': ['list', 'not', 'map'],
        });
        expect(payload.context, isEmpty);
      });

      test('treats null before/after/context values as empty maps', () {
        final payload = AuditLogPayload.fromRaw({
          'before': null,
          'after': null,
          'context': null,
        });
        expect(payload.before, isEmpty);
        expect(payload.after, isEmpty);
        expect(payload.context, isEmpty);
      });

      test('treats boolean before value as empty map', () {
        final payload = AuditLogPayload.fromRaw({
          'before': true,
          'after': false,
          'context': 0,
        });
        expect(payload.before, isEmpty);
        expect(payload.after, isEmpty);
        expect(payload.context, isEmpty);
      });

      // --- ADVERSARIAL: Nested maps ---
      test('preserves nested maps inside before/after', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {
            'config': {'threshold': 0.5, 'enabled': true},
          },
          'after': {
            'config': {'threshold': 0.8, 'enabled': true},
          },
        });
        expect(payload.before['config'], isA<Map>());
        expect((payload.before['config'] as Map)['threshold'], 0.5);
        expect((payload.after['config'] as Map)['threshold'], 0.8);
      });

      // --- ADVERSARIAL: Null values inside maps ---
      test('preserves null values inside before/after maps', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {'name': 'Alice', 'email': null},
          'after': {'name': 'Alice', 'email': 'alice@example.com'},
        });
        expect(payload.before['email'], isNull);
        expect(payload.after['email'], 'alice@example.com');
      });

      // --- ADVERSARIAL: Special characters in keys and values ---
      test('handles special characters in keys and values', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {
            'field with spaces': 'value<script>alert("xss")</script>',
            'émoji_🔑': '日本語テスト',
            "sql'; DROP TABLE--": 'injection_attempt',
          },
          'after': {
            'field with spaces': 'sanitized_value',
            'émoji_🔑': '更新済み',
            "sql'; DROP TABLE--": 'still_here',
          },
        });
        expect(
          payload.before['field with spaces'],
          'value<script>alert("xss")</script>',
        );
        expect(payload.after['émoji_🔑'], '更新済み');
        expect(payload.before["sql'; DROP TABLE--"], 'injection_attempt');
      });
    });

    group('hasDiff', () {
      test('returns true when both before and after are non-empty', () {
        final payload = AuditLogPayload(before: {'a': 1}, after: {'a': 2});
        expect(payload.hasDiff, isTrue);
      });

      test('returns false when before is empty', () {
        final payload = AuditLogPayload(before: const {}, after: {'a': 2});
        expect(payload.hasDiff, isFalse);
      });

      test('returns false when after is empty', () {
        final payload = AuditLogPayload(before: {'a': 1}, after: const {});
        expect(payload.hasDiff, isFalse);
      });

      test('returns false when both are empty', () {
        const payload = AuditLogPayload();
        expect(payload.hasDiff, isFalse);
      });

      test('returns true even when values are identical (non-empty maps)', () {
        // hasDiff only checks non-emptiness, not actual difference
        final payload = AuditLogPayload(
          before: {'a': 'same'},
          after: {'a': 'same'},
        );
        expect(payload.hasDiff, isTrue);
      });
    });

    group('hasContext', () {
      test('returns true when context is non-empty', () {
        final payload = AuditLogPayload(context: {'actor': 'system'});
        expect(payload.hasContext, isTrue);
      });

      test('returns false when context is empty', () {
        const payload = AuditLogPayload();
        expect(payload.hasContext, isFalse);
      });
    });

    group('isEmpty', () {
      test('returns true for default constructor', () {
        const payload = AuditLogPayload();
        expect(payload.isEmpty, isTrue);
      });

      test('returns false when only before has data', () {
        final payload = AuditLogPayload(before: {'x': 1});
        expect(payload.isEmpty, isFalse);
      });

      test('returns false when only after has data', () {
        final payload = AuditLogPayload(after: {'x': 1});
        expect(payload.isEmpty, isFalse);
      });

      test('returns false when only context has data', () {
        final payload = AuditLogPayload(context: {'x': 1});
        expect(payload.isEmpty, isFalse);
      });

      test('returns true for fromRaw(null)', () {
        final payload = AuditLogPayload.fromRaw(null);
        expect(payload.isEmpty, isTrue);
      });
    });

    group('changedKeys', () {
      test('detects changed values', () {
        final payload = AuditLogPayload(
          before: {'status': 'active', 'name': 'Alice'},
          after: {'status': 'suspended', 'name': 'Alice'},
        );
        expect(payload.changedKeys, ['status']);
      });

      test('returns empty list when no values changed', () {
        final payload = AuditLogPayload(
          before: {'a': '1', 'b': '2'},
          after: {'a': '1', 'b': '2'},
        );
        expect(payload.changedKeys, isEmpty);
      });

      test('detects keys present in before but missing in after', () {
        final payload = AuditLogPayload(
          before: {'removed_key': 'value', 'kept': 'same'},
          after: {'kept': 'same'},
        );
        expect(payload.changedKeys, contains('removed_key'));
        expect(payload.changedKeys, isNot(contains('kept')));
      });

      test('detects keys present in after but missing in before', () {
        final payload = AuditLogPayload(
          before: {'kept': 'same'},
          after: {'kept': 'same', 'new_key': 'added'},
        );
        expect(payload.changedKeys, contains('new_key'));
        expect(payload.changedKeys, isNot(contains('kept')));
      });

      test('detects all keys changed when completely different maps', () {
        final payload = AuditLogPayload(
          before: {'a': '1', 'b': '2'},
          after: {'c': '3', 'd': '4'},
        );
        expect(payload.changedKeys, containsAll(['a', 'b', 'c', 'd']));
      });

      // --- CRITICAL FORENSIC TEST: toString coercion behavior ---
      test(
        'FORENSIC: int 1 vs String "1" are treated as SAME due to toString coercion',
        () {
          final payload = AuditLogPayload(
            before: {'count': 1},
            after: {'count': '1'},
          );
          // Both toString() to '1' — this is a known forensic blind spot
          expect(
            payload.changedKeys,
            isEmpty,
            reason:
                'toString coercion makes int 1 and String "1" appear identical. '
                'This is a documented forensic limitation.',
          );
        },
      );

      test(
        'FORENSIC: bool true vs String "true" are treated as SAME due to toString coercion',
        () {
          final payload = AuditLogPayload(
            before: {'enabled': true},
            after: {'enabled': 'true'},
          );
          expect(
            payload.changedKeys,
            isEmpty,
            reason:
                'toString coercion makes bool true and String "true" appear identical.',
          );
        },
      );

      test(
        'FORENSIC: bool false vs String "false" are treated as SAME due to toString coercion',
        () {
          final payload = AuditLogPayload(
            before: {'disabled': false},
            after: {'disabled': 'false'},
          );
          expect(
            payload.changedKeys,
            isEmpty,
            reason:
                'toString coercion makes bool false and String "false" appear identical.',
          );
        },
      );

      test('FORENSIC: null vs empty string are treated as DIFFERENT', () {
        final payload = AuditLogPayload(
          before: {'field': null},
          after: {'field': ''},
        );
        expect(payload.changedKeys, contains('field'));
      });

      test('FORENSIC: null vs String "null" are treated as DIFFERENT', () {
        final payload = AuditLogPayload(
          before: {'field': null},
          after: {'field': 'null'},
        );
        expect(payload.changedKeys, contains('field'));
      });

      test('FORENSIC: double 1.0 vs String "1.0" are treated as SAME', () {
        final payload = AuditLogPayload(
          before: {'score': 1.0},
          after: {'score': '1.0'},
        );
        expect(
          payload.changedKeys,
          isEmpty,
          reason: 'toString coercion makes 1.0 and "1.0" identical.',
        );
      });

      test('detects change when nested map toString differs', () {
        final payload = AuditLogPayload(
          before: {
            'config': {'a': 1},
          },
          after: {
            'config': {'a': 2},
          },
        );
        expect(payload.changedKeys, contains('config'));
      });

      test('does not detect change when nested maps are identical', () {
        final payload = AuditLogPayload(
          before: {
            'config': {'a': 1, 'b': 2},
          },
          after: {
            'config': {'a': 1, 'b': 2},
          },
        );
        expect(payload.changedKeys, isNot(contains('config')));
      });

      // --- ADVERSARIAL: Large payload ---
      test('handles large payloads efficiently', () {
        final before = <String, Object?>{};
        final after = <String, Object?>{};
        for (var i = 0; i < 1000; i++) {
          before['key_$i'] = 'value_$i';
          after['key_$i'] = i.isEven ? 'value_$i' : 'changed_$i';
        }
        final payload = AuditLogPayload(before: before, after: after);
        final changed = payload.changedKeys;
        expect(changed.length, 500);
      });

      // --- ADVERSARIAL: Numeric keys cast to String ---
      test('handles numeric-like string keys', () {
        final payload = AuditLogPayload.fromRaw({
          'before': {'0': 'zero', '1': 'one'},
          'after': {'0': 'zero', '1': 'ONE'},
        });
        expect(payload.changedKeys, ['1']);
      });

      test('returns empty list when both before and after are empty', () {
        const payload = AuditLogPayload();
        expect(payload.changedKeys, isEmpty);
      });

      test('handles keys with only whitespace differences in values', () {
        final payload = AuditLogPayload(
          before: {'name': 'hello'},
          after: {'name': 'hello '},
        );
        expect(payload.changedKeys, contains('name'));
      });
    });

    group('immutability and isolation', () {
      test('fromRaw creates independent copy (mutation isolation)', () {
        final rawBefore = <String, Object?>{'key': 'original'};
        final raw = <String, Object?>{
          'before': rawBefore,
          'after': <String, Object?>{'key': 'modified'},
        };
        final payload = AuditLogPayload.fromRaw(raw);

        // Mutate the original raw map
        rawBefore['key'] = 'tampered';

        // Payload should retain original value (Map.from creates shallow copy)
        expect(payload.before['key'], 'original');
      });
    });
  });
}
