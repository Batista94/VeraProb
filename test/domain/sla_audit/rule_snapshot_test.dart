import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';

void main() {
  group('RuleSnapshotItem', () {
    final Map<String, dynamic> config = {'threshold': 80.0, 'unit': 'km/h'};

    RuleSnapshotItem buildItem({
      String ruleId = 'rule-speed-v1',
      SlaRuleType ruleType = SlaRuleType.excessiveSpeed,
      Map<String, dynamic>? cfg,
      int ruleVersion = 1,
      int evaluationOrder = 0,
    }) => RuleSnapshotItem(
      ruleId: ruleId,
      ruleType: ruleType,
      config: cfg ?? config,
      ruleVersion: ruleVersion,
      evaluationOrder: evaluationOrder,
    );

    test('fromJson reconstructs item correctly', () {
      final json = {
        'ruleId': 'rule-delay-v2',
        'ruleType': 'MAX_TOLERANCE_DELAY',
        'config': {'threshold_minutes': 10},
        'ruleVersion': 2,
        'evaluationOrder': 1,
      };
      final item = RuleSnapshotItem.fromJson(json);
      expect(item.ruleId, 'rule-delay-v2');
      expect(item.ruleType, SlaRuleType.maxToleranceDelay);
      expect(item.config['threshold_minutes'], 10);
      expect(item.ruleVersion, 2);
      expect(item.evaluationOrder, 1);
    });

    test('toJson serializes item correctly', () {
      final item = buildItem();
      final json = item.toJson();
      expect(json['ruleId'], 'rule-speed-v1');
      expect(json['ruleType'], 'EXCESSIVE_SPEED');
      expect(json['config'], config);
      expect(json['ruleVersion'], 1);
      expect(json['evaluationOrder'], 0);
    });

    test('equality based on props', () {
      final i1 = buildItem();
      final i2 = buildItem();
      expect(i1, equals(i2));
    });

    test('props differ when ruleId differs', () {
      final i1 = buildItem(ruleId: 'rule-a');
      final i2 = buildItem(ruleId: 'rule-b');
      expect(i1, isNot(equals(i2)));
    });
  });

  group('RuleSnapshot', () {
    RuleSnapshotItem makeItem(int order, SlaRuleType type) => RuleSnapshotItem(
      ruleId: 'rule-$order',
      ruleType: type,
      config: {},
      ruleVersion: 1,
      evaluationOrder: order,
    );

    test('orderedRules returns items sorted by evaluationOrder ascending', () {
      final snapshot = RuleSnapshot([
        makeItem(2, SlaRuleType.maxEvidenceGap),
        makeItem(0, SlaRuleType.excessiveSpeed),
        makeItem(1, SlaRuleType.maxToleranceDelay),
      ]);
      final ordered = snapshot.orderedRules;
      expect(ordered[0].evaluationOrder, 0);
      expect(ordered[1].evaluationOrder, 1);
      expect(ordered[2].evaluationOrder, 2);
    });

    test('fromJson builds snapshot from list', () {
      final jsonList = [
        {
          'ruleId': 'rule-1',
          'ruleType': 'EXCESSIVE_SPEED',
          'config': <String, dynamic>{},
          'ruleVersion': 1,
          'evaluationOrder': 0,
        },
        {
          'ruleId': 'rule-2',
          'ruleType': 'NO_SHOW_PENALTY',
          'config': <String, dynamic>{},
          'ruleVersion': 1,
          'evaluationOrder': 1,
        },
      ];
      final snapshot = RuleSnapshot.fromJson(jsonList);
      expect(snapshot.rules.length, 2);
      expect(snapshot.rules[0].ruleId, 'rule-1');
      expect(snapshot.rules[1].ruleId, 'rule-2');
    });

    test('toJson serializes rules list', () {
      final snapshot = RuleSnapshot([makeItem(0, SlaRuleType.excessiveSpeed)]);
      final json = snapshot.toJson();
      expect(json.length, 1);
      expect(json[0]['ruleId'], 'rule-0');
    });

    test('equality based on rules', () {
      final s1 = RuleSnapshot([makeItem(0, SlaRuleType.noShowPenalty)]);
      final s2 = RuleSnapshot([makeItem(0, SlaRuleType.noShowPenalty)]);
      expect(s1, equals(s2));
    });

    test('empty snapshot orderedRules returns empty list', () {
      const snapshot = RuleSnapshot([]);
      expect(snapshot.orderedRules, isEmpty);
    });

    test(
      'INV-15: serialize(deserialize(serialize(x))) == serialize(x) for byte-by-byte stability',
      () {
        const snapshot = RuleSnapshot([
          RuleSnapshotItem(
            ruleId: '123e4567-e89b-12d3-a456-426614174000',
            ruleType: SlaRuleType.maxToleranceDelay,
            config: {'threshold_minutes': 15, 'allow_grace': true},
            ruleVersion: 2,
            evaluationOrder: 1,
          ),
          RuleSnapshotItem(
            ruleId: '223e4567-e89b-12d3-a456-426614174001',
            ruleType: SlaRuleType.maxEvidenceGap,
            config: {'max_gap_seconds': 300},
            ruleVersion: 1,
            evaluationOrder: 2,
          ),
        ]);

        // serialize(x)
        final step1JsonList = snapshot.toJson();
        final step1String = jsonEncode(step1JsonList);

        // deserialize(serialize(x))
        final step2DecodedList = jsonDecode(step1String) as List<dynamic>;
        final step2Snapshot = RuleSnapshot.fromJson(step2DecodedList);

        // serialize(deserialize(serialize(x)))
        final step3JsonList = step2Snapshot.toJson();
        final step3String = jsonEncode(step3JsonList);

        // Byte-by-byte string stability
        expect(step3String, equals(step1String));

        // Structural equality check
        expect(step2Snapshot, equals(snapshot));
      },
    );
  });
}
