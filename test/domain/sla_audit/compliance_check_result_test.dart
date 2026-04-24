// TDD: Tests written BEFORE implementation (Red phase).
// ComplianceCheckResult model + SlaRuleType.requiredEvidence.
//
// Adversarial scenarios: malformed JSON, null fields, empty arrays,
// type mismatches, boundary conditions.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/telegram/compliance_check_result.dart';

void main() {
  // =========================================================================
  // SlaRuleType — REQUIRED_EVIDENCE
  // =========================================================================
  group('SlaRuleType.requiredEvidence', () {
    test('fromString parses REQUIRED_EVIDENCE', () {
      expect(
        SlaRuleType.fromString('REQUIRED_EVIDENCE'),
        SlaRuleType.requiredEvidence,
      );
    });

    test('value returns REQUIRED_EVIDENCE', () {
      expect(SlaRuleType.requiredEvidence.value, 'REQUIRED_EVIDENCE');
    });

    test('round-trip through fromString', () {
      const type = SlaRuleType.requiredEvidence;
      expect(SlaRuleType.fromString(type.value), type);
    });
  });

  // =========================================================================
  // ComplianceCheckItem — Equatable + construction
  // =========================================================================
  group('ComplianceCheckItem', () {
    test('constructs with all fields', () {
      const item = ComplianceCheckItem(
        typeKey: 'estado',
        isFulfilled: true,
        count: 2,
      );
      expect(item.typeKey, 'estado');
      expect(item.isFulfilled, isTrue);
      expect(item.count, 2);
    });

    test('label resolves known category', () {
      expect(
        const ComplianceCheckItem(
          typeKey: 'estado',
          isFulfilled: false,
          count: 0,
        ).label,
        'Estado / Visual',
      );
      expect(
        const ComplianceCheckItem(
          typeKey: 'doc',
          isFulfilled: false,
          count: 0,
        ).label,
        'Documental / NF',
      );
      expect(
        const ComplianceCheckItem(
          typeKey: 'oper',
          isFulfilled: false,
          count: 0,
        ).label,
        'Operacional',
      );
      expect(
        const ComplianceCheckItem(
          typeKey: 'incidente',
          isFulfilled: false,
          count: 0,
        ).label,
        'Incidente / SLA',
      );
      expect(
        const ComplianceCheckItem(
          typeKey: 'outros',
          isFulfilled: false,
          count: 0,
        ).label,
        'Outros / Info',
      );
    });

    test('label returns typeKey for unknown category', () {
      expect(
        const ComplianceCheckItem(
          typeKey: 'xpto',
          isFulfilled: false,
          count: 0,
        ).label,
        'xpto',
      );
    });

    test('Equatable: same fields → equal', () {
      const a = ComplianceCheckItem(
        typeKey: 'doc',
        isFulfilled: true,
        count: 1,
      );
      const b = ComplianceCheckItem(
        typeKey: 'doc',
        isFulfilled: true,
        count: 1,
      );
      expect(a, equals(b));
    });

    test('Equatable: different count → NOT equal', () {
      const a = ComplianceCheckItem(
        typeKey: 'doc',
        isFulfilled: true,
        count: 1,
      );
      const b = ComplianceCheckItem(
        typeKey: 'doc',
        isFulfilled: true,
        count: 2,
      );
      expect(a, isNot(equals(b)));
    });

    test('Equatable: different isFulfilled → NOT equal', () {
      const a = ComplianceCheckItem(
        typeKey: 'doc',
        isFulfilled: true,
        count: 1,
      );
      const b = ComplianceCheckItem(
        typeKey: 'doc',
        isFulfilled: false,
        count: 1,
      );
      expect(a, isNot(equals(b)));
    });
  });

  // =========================================================================
  // ComplianceCheckResult.fromJson — all 3 variants
  // =========================================================================
  group('ComplianceCheckResult.fromJson', () {
    test('active compliance — happy path', () {
      final json = {
        'status': 'active',
        'set_id': 'SET-abc123',
        'items': [
          {'type_key': 'estado', 'is_fulfilled': true, 'count': 2},
          {'type_key': 'doc', 'is_fulfilled': false, 'count': 0},
          {'type_key': 'oper', 'is_fulfilled': true, 'count': 1},
        ],
        'total_required': 3,
        'total_fulfilled': 2,
      };
      final result = ComplianceCheckResult.fromJson(json);

      expect(result, isA<ActiveCompliance>());
      final active = result as ActiveCompliance;
      expect(active.setId, 'SET-abc123');
      expect(active.items, hasLength(3));
      expect(active.totalRequired, 3);
      expect(active.totalFulfilled, 2);
      expect(active.items[0].typeKey, 'estado');
      expect(active.items[0].isFulfilled, isTrue);
      expect(active.items[0].count, 2);
      expect(active.items[1].isFulfilled, isFalse);
    });

    test('no active trip', () {
      final json = {'status': 'no_active_trip'};
      final result = ComplianceCheckResult.fromJson(json);
      expect(result, isA<NoActiveTrip>());
    });

    test('no requirements — with evidence count', () {
      final json = {
        'status': 'no_requirements',
        'set_id': 'SET-xyz',
        'evidence_count': 5,
      };
      final result = ComplianceCheckResult.fromJson(json);

      expect(result, isA<NoRequirements>());
      final nr = result as NoRequirements;
      expect(nr.setId, 'SET-xyz');
      expect(nr.evidenceCount, 5);
    });

    test('all fulfilled — 3/3', () {
      final json = {
        'status': 'active',
        'set_id': 'SET-full',
        'items': [
          {'type_key': 'estado', 'is_fulfilled': true, 'count': 1},
          {'type_key': 'doc', 'is_fulfilled': true, 'count': 1},
          {'type_key': 'oper', 'is_fulfilled': true, 'count': 1},
        ],
        'total_required': 3,
        'total_fulfilled': 3,
      };
      final result = ComplianceCheckResult.fromJson(json) as ActiveCompliance;
      expect(result.isComplete, isTrue);
      expect(result.pendingCount, 0);
    });

    test('none fulfilled — 0/3', () {
      final json = {
        'status': 'active',
        'set_id': 'SET-empty',
        'items': [
          {'type_key': 'estado', 'is_fulfilled': false, 'count': 0},
          {'type_key': 'doc', 'is_fulfilled': false, 'count': 0},
          {'type_key': 'oper', 'is_fulfilled': false, 'count': 0},
        ],
        'total_required': 3,
        'total_fulfilled': 0,
      };
      final result = ComplianceCheckResult.fromJson(json) as ActiveCompliance;
      expect(result.isComplete, isFalse);
      expect(result.pendingCount, 3);
      expect(result.pendingItems, hasLength(3));
    });
  });

  // =========================================================================
  // ComplianceCheckResult.fromJson — adversarial / malformed
  // =========================================================================
  group('ComplianceCheckResult.fromJson — adversarial', () {
    test('unknown status → throws ArgumentError', () {
      expect(
        () => ComplianceCheckResult.fromJson({'status': 'INVALID'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('missing status key → throws', () {
      expect(() => ComplianceCheckResult.fromJson({}), throwsA(isA<Object>()));
    });

    test('null status → throws', () {
      expect(
        () => ComplianceCheckResult.fromJson({'status': null}),
        throwsA(isA<Object>()),
      );
    });

    test('active with empty items array → 0/0', () {
      final json = {
        'status': 'active',
        'set_id': 'SET-x',
        'items': <dynamic>[],
        'total_required': 0,
        'total_fulfilled': 0,
      };
      final result = ComplianceCheckResult.fromJson(json) as ActiveCompliance;
      expect(result.items, isEmpty);
      expect(result.isComplete, isTrue); // 0/0 = complete
    });

    test('active with null items → throws', () {
      final json = {
        'status': 'active',
        'set_id': 'SET-x',
        'items': null,
        'total_required': 0,
        'total_fulfilled': 0,
      };
      expect(
        () => ComplianceCheckResult.fromJson(json),
        throwsA(isA<Object>()),
      );
    });

    test('no_requirements with evidence_count=0', () {
      final json = {
        'status': 'no_requirements',
        'set_id': 'SET-y',
        'evidence_count': 0,
      };
      final result = ComplianceCheckResult.fromJson(json) as NoRequirements;
      expect(result.evidenceCount, 0);
    });

    test('item with count as double → throws TypeError', () {
      final json = {
        'status': 'active',
        'set_id': 'SET-x',
        'items': [
          {'type_key': 'estado', 'is_fulfilled': true, 'count': 1.5},
        ],
        'total_required': 1,
        'total_fulfilled': 1,
      };
      // count must be int — double should fail
      expect(
        () => ComplianceCheckResult.fromJson(json),
        throwsA(isA<Object>()),
      );
    });
  });

  // =========================================================================
  // ActiveCompliance — convenience getters
  // =========================================================================
  group('ActiveCompliance — convenience getters', () {
    ActiveCompliance make({
      required int fulfilled,
      required int required,
      List<ComplianceCheckItem>? items,
    }) {
      return ActiveCompliance(
        setId: 'SET-test',
        items:
            items ??
            List.generate(
              required,
              (i) => ComplianceCheckItem(
                typeKey: 'type_$i',
                isFulfilled: i < fulfilled,
                count: i < fulfilled ? 1 : 0,
              ),
            ),
        totalRequired: required,
        totalFulfilled: fulfilled,
      );
    }

    test('isComplete true when fulfilled == required', () {
      expect(make(fulfilled: 3, required: 3).isComplete, isTrue);
    });

    test('isComplete false when fulfilled < required', () {
      expect(make(fulfilled: 2, required: 3).isComplete, isFalse);
    });

    test('isComplete true when both are 0', () {
      expect(make(fulfilled: 0, required: 0, items: []).isComplete, isTrue);
    });

    test('pendingCount = required - fulfilled', () {
      expect(make(fulfilled: 1, required: 3).pendingCount, 2);
    });

    test('pendingItems returns only unfulfilled items', () {
      final result = make(fulfilled: 1, required: 3);
      expect(result.pendingItems, hasLength(2));
      expect(result.pendingItems.every((i) => !i.isFulfilled), isTrue);
    });

    test('fulfilledItems returns only fulfilled items', () {
      final result = make(fulfilled: 2, required: 3);
      expect(result.fulfilledItems, hasLength(2));
      expect(result.fulfilledItems.every((i) => i.isFulfilled), isTrue);
    });
  });

  // =========================================================================
  // Equatable — ComplianceCheckResult variants
  // =========================================================================
  group('Equatable — ComplianceCheckResult', () {
    test('NoActiveTrip instances are equal', () {
      expect(const NoActiveTrip(), equals(const NoActiveTrip()));
    });

    test('NoRequirements with same fields → equal', () {
      expect(
        const NoRequirements(setId: 'S1', evidenceCount: 5),
        equals(const NoRequirements(setId: 'S1', evidenceCount: 5)),
      );
    });

    test('NoRequirements with different count → NOT equal', () {
      expect(
        const NoRequirements(setId: 'S1', evidenceCount: 5),
        isNot(equals(const NoRequirements(setId: 'S1', evidenceCount: 3))),
      );
    });

    test('ActiveCompliance with same items → equal', () {
      final items = [
        const ComplianceCheckItem(typeKey: 'doc', isFulfilled: true, count: 1),
      ];
      expect(
        ActiveCompliance(
          setId: 'S1',
          items: items,
          totalRequired: 1,
          totalFulfilled: 1,
        ),
        equals(
          ActiveCompliance(
            setId: 'S1',
            items: items,
            totalRequired: 1,
            totalFulfilled: 1,
          ),
        ),
      );
    });

    test('different variants are NOT equal', () {
      expect(
        const NoActiveTrip(),
        isNot(equals(const NoRequirements(setId: 'S1', evidenceCount: 0))),
      );
    });
  });
}
