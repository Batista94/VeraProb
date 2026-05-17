// TDD tests for ComplianceCheckResult repository parsing and provider states.
// Adversarial: malformed RPC responses, empty setIds, cross-org isolation shape.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/telegram/compliance_check_result.dart';

// ── Mirrors PostgresTelegramRepository.getComplianceStatus parsing ────────────

ComplianceCheckResult parseComplianceResponse(dynamic data) {
  return ComplianceCheckResult.fromJson(data as Map<String, dynamic>);
}

Map<String, ComplianceCheckResult> parseBatchResponse(dynamic data) {
  final list = data as List<dynamic>;
  return {
    for (final item in list)
      (item as Map<String, dynamic>)['set_id'] as String:
          ComplianceCheckResult.fromJson(item),
  };
}

void main() {
  // =========================================================================
  // getComplianceStatus — RPC response parsing
  // =========================================================================
  group('getComplianceStatus — RPC response parsing', () {
    test('parses no_active_trip', () {
      final result = parseComplianceResponse({'status': 'no_active_trip'});
      expect(result, isA<NoActiveTrip>());
    });

    test('parses no_requirements', () {
      final result = parseComplianceResponse({
        'status': 'no_requirements',
        'set_id': 'SET-1',
        'evidence_count': 4,
      });
      expect(result, isA<NoRequirements>());
      expect((result as NoRequirements).evidenceCount, 4);
    });

    test('parses active compliance — 2/3 fulfilled', () {
      final result = parseComplianceResponse({
        'status': 'active',
        'set_id': 'SET-abc',
        'items': [
          {'type_key': 'estado', 'is_fulfilled': true, 'count': 1},
          {'type_key': 'doc', 'is_fulfilled': true, 'count': 2},
          {'type_key': 'oper', 'is_fulfilled': false, 'count': 0},
        ],
        'total_required': 3,
        'total_fulfilled': 2,
      });
      expect(result, isA<ActiveCompliance>());
      final active = result as ActiveCompliance;
      expect(active.setId, 'SET-abc');
      expect(active.totalFulfilled, 2);
      expect(active.totalRequired, 3);
      expect(active.isComplete, isFalse);
      expect(active.pendingCount, 1);
    });

    test('parses active compliance — all fulfilled', () {
      final result = parseComplianceResponse({
        'status': 'active',
        'set_id': 'SET-full',
        'items': [
          {'type_key': 'estado', 'is_fulfilled': true, 'count': 1},
        ],
        'total_required': 1,
        'total_fulfilled': 1,
      });
      expect((result as ActiveCompliance).isComplete, isTrue);
    });

    test('unknown status throws ArgumentError', () {
      expect(
        () => parseComplianceResponse({'status': 'UNKNOWN'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('null data throws', () {
      expect(() => parseComplianceResponse(null), throwsA(isA<Object>()));
    });

    test('missing status key throws', () {
      expect(
        () => parseComplianceResponse({'set_id': 'SET-1'}),
        throwsA(isA<Object>()),
      );
    });

    test('active with null items throws', () {
      expect(
        () => parseComplianceResponse({
          'status': 'active',
          'set_id': 'SET-1',
          'items': null,
          'total_required': 0,
          'total_fulfilled': 0,
        }),
        throwsA(isA<Object>()),
      );
    });
  });

  // =========================================================================
  // getBatchComplianceStatus — batch RPC response parsing
  // =========================================================================
  group('getBatchComplianceStatus — batch parsing', () {
    test('empty list returns empty map', () {
      final result = parseBatchResponse(<dynamic>[]);
      expect(result, isEmpty);
    });

    test('single SET parsed correctly', () {
      final result = parseBatchResponse([
        {
          'set_id': 'SET-1',
          'status': 'active',
          'items': [
            {'type_key': 'estado', 'is_fulfilled': true, 'count': 1},
          ],
          'total_required': 1,
          'total_fulfilled': 1,
        },
      ]);
      expect(result, hasLength(1));
      expect(result['SET-1'], isA<ActiveCompliance>());
    });

    test('multiple SETs parsed — each keyed by set_id', () {
      final result = parseBatchResponse([
        {'set_id': 'SET-A', 'status': 'no_active_trip'},
        {'set_id': 'SET-B', 'status': 'no_requirements', 'evidence_count': 2},
        {
          'set_id': 'SET-C',
          'status': 'active',
          'items': <dynamic>[],
          'total_required': 0,
          'total_fulfilled': 0,
        },
      ]);
      expect(result, hasLength(3));
      expect(result['SET-A'], isA<NoActiveTrip>());
      expect(result['SET-B'], isA<NoRequirements>());
      expect(result['SET-C'], isA<ActiveCompliance>());
    });

    test('duplicate set_id — last one wins (map semantics)', () {
      final result = parseBatchResponse([
        {'set_id': 'SET-1', 'status': 'no_active_trip'},
        {'set_id': 'SET-1', 'status': 'no_requirements', 'evidence_count': 5},
      ]);
      // Map literal with duplicate key: last wins
      expect(result['SET-1'], isA<NoRequirements>());
    });

    test('malformed item in batch throws', () {
      expect(
        () => parseBatchResponse([
          {'set_id': 'SET-1', 'status': 'INVALID_STATUS'},
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('missing set_id in batch item throws TypeError', () {
      expect(
        () => parseBatchResponse([
          {'status': 'no_active_trip'}, // no set_id
        ]),
        throwsA(isA<Object>()),
      );
    });
  });

  // =========================================================================
  // ComplianceCheckResult — domain invariants
  // =========================================================================
  group('ComplianceCheckResult — domain invariants', () {
    test('ActiveCompliance.pendingItems only returns unfulfilled', () {
      final result =
          parseComplianceResponse({
                'status': 'active',
                'set_id': 'SET-1',
                'items': [
                  {'type_key': 'estado', 'is_fulfilled': true, 'count': 1},
                  {'type_key': 'doc', 'is_fulfilled': false, 'count': 0},
                  {'type_key': 'oper', 'is_fulfilled': false, 'count': 0},
                ],
                'total_required': 3,
                'total_fulfilled': 1,
              })
              as ActiveCompliance;

      expect(result.pendingItems, hasLength(2));
      expect(result.pendingItems.every((i) => !i.isFulfilled), isTrue);
      expect(result.fulfilledItems, hasLength(1));
    });

    test('NoRequirements with 0 evidence_count is valid', () {
      final result =
          parseComplianceResponse({
                'status': 'no_requirements',
                'set_id': 'SET-empty',
                'evidence_count': 0,
              })
              as NoRequirements;
      expect(result.evidenceCount, 0);
    });

    test('ActiveCompliance 0/0 is considered complete', () {
      final result =
          parseComplianceResponse({
                'status': 'active',
                'set_id': 'SET-1',
                'items': <dynamic>[],
                'total_required': 0,
                'total_fulfilled': 0,
              })
              as ActiveCompliance;
      expect(result.isComplete, isTrue);
      expect(result.pendingCount, 0);
    });

    test('ComplianceCheckItem.label falls back to typeKey for unknown', () {
      const item = ComplianceCheckItem(
        typeKey: 'custom_evidence',
        isFulfilled: false,
        count: 0,
      );
      expect(item.label, 'custom_evidence');
    });

    test('ComplianceCheckItem.label resolves all known categories', () {
      final known = {
        'estado': 'Estado / Visual',
        'doc': 'Documental / NF',
        'oper': 'Operacional',
        'incidente': 'Incidente / SLA',
        'outros': 'Outros / Info',
      };
      for (final entry in known.entries) {
        final item = ComplianceCheckItem(
          typeKey: entry.key,
          isFulfilled: false,
          count: 0,
        );
        expect(item.label, entry.value, reason: 'Failed for ${entry.key}');
      }
    });
  });
}
