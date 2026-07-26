import 'package:test/test.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';

void main() {
  group('SandboxSimulationOverrides', () {
    test('SandboxRuleOverride serializes and deserializes correctly', () {
      const override = SandboxRuleOverride(
        ruleType: SlaRuleType.maxToleranceDelay,
        ruleConfig: {'threshold_minutes': 60, 'fine_cents': 500},
      );

      final json = override.toJson();
      expect(json['rule_type'], 'MAX_TOLERANCE_DELAY');
      expect(json['rule_config']['threshold_minutes'], 60);

      final fromJson = SandboxRuleOverride.fromJson(json);
      expect(fromJson.ruleType, SlaRuleType.maxToleranceDelay);
      expect(fromJson.ruleConfig, {'threshold_minutes': 60, 'fine_cents': 500});
      expect(fromJson, override); // Equatable test
    });

    test('SandboxFinancialOverrides serializes and deserializes correctly', () {
      const overrides = SandboxFinancialOverrides(
        monthlyPenaltyCapCents: 10000,
        baseFineCents: 1500,
      );

      final json = overrides.toJson();
      expect(json['monthly_penalty_cap_cents'], 10000);
      expect(json['base_fine_cents'], 1500);

      final fromJson = SandboxFinancialOverrides.fromJson(json);
      expect(fromJson.monthlyPenaltyCapCents, 10000);
      expect(fromJson.baseFineCents, 1500);
      expect(fromJson, overrides);
    });

    test(
      'SandboxSimulationOverrides serializes and deserializes empty/null fields safely',
      () {
        const overrides = SandboxSimulationOverrides();

        final json = overrides.toJson();
        expect(json['overrides'], isEmpty);
        expect(json.containsKey('financial_overrides'), isFalse);

        final fromJson = SandboxSimulationOverrides.fromJson(json);
        expect(fromJson.overrides, isEmpty);
        expect(fromJson.financialOverrides, isNull);
        expect(fromJson, overrides);
      },
    );

    test('validate throws on empty ruleConfig', () {
      const overrides = SandboxSimulationOverrides(
        overrides: [
          SandboxRuleOverride(
            ruleType: SlaRuleType.maxEvidenceGap,
            ruleConfig: {},
          ),
        ],
      );

      expect(
        () => overrides.validate(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('Configuração vazia'),
          ),
        ),
      );
    });

    test('validate throws on negative financial overrides', () {
      const negCap = SandboxSimulationOverrides(
        financialOverrides: SandboxFinancialOverrides(
          monthlyPenaltyCapCents: -1,
        ),
      );
      expect(
        () => negCap.validate(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('negativo'),
          ),
        ),
      );

      const negFine = SandboxSimulationOverrides(
        financialOverrides: SandboxFinancialOverrides(baseFineCents: -5),
      );
      expect(
        () => negFine.validate(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('negativa'),
          ),
        ),
      );
    });
  });
}
