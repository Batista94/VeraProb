import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_rule_view.dart';

void main() {
  group('ContractualRuleView', () {
    test('can be constructed with required fields', () {
      final now = DateTime.utc(2026, 1, 1);
      final view = ContractualRuleView(
        id: 'rule-1',
        ruleSetId: 'rs-1',
        ruleType: 'NoShowRule',
        config: {'threshold_minutes': 60},
        ruleVersion: 1,
        evaluationOrder: 1,
        activeFromUtc: now,
        isActive: true,
      );
      expect(view.id, 'rule-1');
      expect(view.ruleType, 'NoShowRule');
      expect(view.isActive, isTrue);
    });

    test('config field is Map<String, Object?> — no dynamic', () {
      final now = DateTime.utc(2026, 1, 1);
      final view = ContractualRuleView(
        id: 'rule-2',
        ruleSetId: 'rs-1',
        ruleType: 'DelayRule',
        config: {'penalty_bps': 10000, 'tolerance_minutes': 5},
        ruleVersion: 2,
        evaluationOrder: 2,
        activeFromUtc: now,
        isActive: true,
      );
      // config must be typed Map<String, Object?>, not Map<String, dynamic>
      expect(view.config, isA<Map<String, Object?>>());
      expect(view.config['penalty_bps'], 10000);
    });

    test('activeToUtc is optional', () {
      final now = DateTime.utc(2026, 1, 1);
      final view = ContractualRuleView(
        id: 'rule-3',
        ruleSetId: 'rs-1',
        ruleType: 'DowngradeRule',
        config: {},
        ruleVersion: 1,
        evaluationOrder: 3,
        activeFromUtc: now,
        isActive: false,
        activeToUtc: DateTime.utc(2026, 12, 31),
      );
      expect(view.activeToUtc, isNotNull);
    });
  });
}
