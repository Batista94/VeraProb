import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_state.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';

void main() {
  group('SandboxWizardState — UI Reais → Domain cents (INV-4)', () {
    test('R\$ 5.000,00 masked string converts to 500000 cents', () {
      const masked = 'R\$ 5.000,00';
      final cents = BrlCurrencyInputFormatter.toCents(masked);

      expect(cents, isA<int>());
      expect(cents, 500000);

      final state = SandboxWizardState(
        sessionLabel: 'Cap 5k',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
        monthlyPenaltyCapCents: cents,
      );

      final overrides = state.buildOverrides();
      expect(overrides.financialOverrides?.monthlyPenaltyCapCents, isA<int>());
      expect(overrides.financialOverrides?.monthlyPenaltyCapCents, 500000);
    });

    test(
      'base fine R\$ 150,00 → 15000 cents in SandboxSimulationOverrides',
      () {
        final cents = BrlCurrencyInputFormatter.toCents('R\$ 150,00');
        expect(cents, 15000);

        final overrides = SandboxWizardState(
          sessionLabel: 'Base',
          contractId: 'ct-1',
          periodStartUtc: DateTime.utc(2026, 1, 1),
          periodEndUtc: DateTime.utc(2026, 2, 1),
          baseFineCents: cents,
        ).buildOverrides();

        expect(overrides.financialOverrides?.baseFineCents, isA<int>());
        expect(overrides.financialOverrides?.baseFineCents, 15000);
      },
    );

    test('buildOverrides includes delay tolerance rule when slider set', () {
      final overrides = SandboxWizardState(
        sessionLabel: 'Tol 20',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
        delayToleranceMinutes: 20,
      ).buildOverrides();

      expect(overrides.overrides, hasLength(1));
      expect(overrides.overrides.first.ruleType, SlaRuleType.maxToleranceDelay);
      expect(overrides.overrides.first.ruleConfig['threshold_minutes'], 20);
      expect(
        overrides.overrides.first.ruleConfig['threshold_minutes'],
        isA<int>(),
      );
    });

    test('buildOverrides omits financial block when cents are null', () {
      final overrides = SandboxWizardState(
        sessionLabel: 'Só regras',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
        delayToleranceMinutes: 15,
      ).buildOverrides();

      expect(overrides.financialOverrides, isNull);
      expect(overrides, isA<SandboxSimulationOverrides>());
    });

    test('copyWith preserves cents as int through form updates', () {
      final initial = SandboxWizardState(
        sessionLabel: 'A',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
      );

      final updated = initial.copyWith(
        monthlyPenaltyCapCents: BrlCurrencyInputFormatter.toCents(
          'R\$ 5.000,00',
        ),
        baseFineCents: BrlCurrencyInputFormatter.toCents('R\$ 150,00'),
      );

      expect(updated.monthlyPenaltyCapCents, 500000);
      expect(updated.baseFineCents, 15000);
      expect(updated.monthlyPenaltyCapCents.runtimeType, int);
      expect(updated.baseFineCents.runtimeType, int);
    });
  });
}
