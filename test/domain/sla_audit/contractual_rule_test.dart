import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  final baseTime = DateTime.utc(2026, 1, 1);

  ContractualRule makeRule({
    SlaRuleType type = SlaRuleType.maxToleranceDelay,
    DateTime? activeToUtc,
    int evaluationOrder = 1,
    int ruleVersion = 1,
  }) {
    return ContractualRule(
      id: 'rule-1',
      ruleSetId: 'ruleset-1',
      ruleType: type,
      config: {'threshold_seconds': 300},
      ruleVersion: ruleVersion,
      evaluationOrder: evaluationOrder,
      activeFromUtc: baseTime,
      activeToUtc: activeToUtc,
      createdAtUtc: baseTime,
    );
  }

  group('SlaRuleType.fromString', () {
    test('parses MAX_TOLERANCE_DELAY', () {
      expect(
        SlaRuleType.fromString('MAX_TOLERANCE_DELAY'),
        SlaRuleType.maxToleranceDelay,
      );
    });

    test('parses MAX_EVIDENCE_GAP', () {
      expect(
        SlaRuleType.fromString('MAX_EVIDENCE_GAP'),
        SlaRuleType.maxEvidenceGap,
      );
    });

    test('parses MIN_GEOFENCE_COVERAGE', () {
      expect(
        SlaRuleType.fromString('MIN_GEOFENCE_COVERAGE'),
        SlaRuleType.minGeofenceCoverage,
      );
    });

    test('parses NO_SHOW_PENALTY', () {
      expect(
        SlaRuleType.fromString('NO_SHOW_PENALTY'),
        SlaRuleType.noShowPenalty,
      );
    });

    test('parses EXCESSIVE_SPEED', () {
      expect(
        SlaRuleType.fromString('EXCESSIVE_SPEED'),
        SlaRuleType.excessiveSpeed,
      );
    });

    test('all enum values round-trip through fromString', () {
      for (final type in SlaRuleType.values) {
        expect(SlaRuleType.fromString(type.value), type);
      }
    });

    test('throws ArgumentError for unknown value', () {
      expect(
        () => SlaRuleType.fromString('UNKNOWN_RULE'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('throws ArgumentError for empty string', () {
      expect(
        () => SlaRuleType.fromString(''),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('is case-sensitive', () {
      expect(
        () => SlaRuleType.fromString('max_tolerance_delay'),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  group('ContractualRule.isActive', () {
    test('isActive is true when activeToUtc is null', () {
      final rule = makeRule(activeToUtc: null);
      expect(rule.isActive, isTrue);
    });

    test('isActive is false when activeToUtc is set', () {
      final rule = makeRule(activeToUtc: DateTime.utc(2026, 6, 30));
      expect(rule.isActive, isFalse);
    });
  });

  group('ContractualRule — equality and props', () {
    test('two rules with same fields are equal', () {
      final r1 = makeRule();
      final r2 = makeRule();
      expect(r1, equals(r2));
    });

    test('rules with different ruleVersion are not equal', () {
      final r1 = makeRule(ruleVersion: 1);
      final r2 = makeRule(ruleVersion: 2);
      expect(r1, isNot(equals(r2)));
    });

    test('rules with different evaluationOrder are not equal', () {
      final r1 = makeRule(evaluationOrder: 1);
      final r2 = makeRule(evaluationOrder: 2);
      expect(r1, isNot(equals(r2)));
    });

    test('rules with different ruleType are not equal', () {
      final r1 = makeRule(type: SlaRuleType.maxToleranceDelay);
      final r2 = makeRule(type: SlaRuleType.noShowPenalty);
      expect(r1, isNot(equals(r2)));
    });
  });

  group('ContractualRule — field access', () {
    test('config is accessible as map', () {
      final rule = ContractualRule(
        id: 'rule-x',
        ruleSetId: 'rs-1',
        ruleType: SlaRuleType.excessiveSpeed,
        config: {'speed_limit_kmh': 80, 'penalty_cents': 5000},
        ruleVersion: 3,
        evaluationOrder: 2,
        activeFromUtc: baseTime,
        createdAtUtc: baseTime,
      );
      expect(rule.config['speed_limit_kmh'], 80);
      expect(rule.config['penalty_cents'], 5000);
    });
  });
}
