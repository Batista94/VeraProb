import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/sandbox/validators/sandbox_wizard_validator.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_state.dart';

void main() {
  group('SandboxWizardValidator — period cap', () {
    test('period longer than 6 months returns max-period error', () {
      final state = SandboxWizardState(
        sessionLabel: 'Teste',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 8, 1), // > 6 months
      );

      final errors = SandboxWizardValidator.validate(state);

      expect(errors, contains('O período máximo permitido é de 6 meses'));
    });

    test('period of exactly 183 days is accepted', () {
      final start = DateTime.utc(2026, 1, 1);
      final state = SandboxWizardState(
        sessionLabel: 'Teste',
        contractId: 'ct-1',
        periodStartUtc: start,
        periodEndUtc: start.add(const Duration(days: 183)),
      );

      final errors = SandboxWizardValidator.validate(state);
      expect(
        errors,
        isNot(contains('O período máximo permitido é de 6 meses')),
      );
    });

    test('period of 184 days is rejected', () {
      final start = DateTime.utc(2026, 1, 1);
      final state = SandboxWizardState(
        sessionLabel: 'Teste',
        contractId: 'ct-1',
        periodStartUtc: start,
        periodEndUtc: start.add(const Duration(days: 184)),
      );

      expect(
        SandboxWizardValidator.validate(state),
        contains('O período máximo permitido é de 6 meses'),
      );
    });
  });

  group('SandboxWizardValidator — required fields', () {
    test('empty session label is rejected', () {
      final state = SandboxWizardState(
        sessionLabel: '   ',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
      );

      expect(
        SandboxWizardValidator.validate(state),
        contains('Informe o nome da sessão'),
      );
    });

    test('null/empty contract is rejected', () {
      final state = SandboxWizardState(
        sessionLabel: 'Sessão A',
        contractId: null,
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
      );

      expect(
        SandboxWizardValidator.validate(state),
        contains('Selecione um contrato'),
      );

      expect(
        SandboxWizardValidator.validate(state.copyWith(contractId: '')),
        contains('Selecione um contrato'),
      );
    });

    test('missing period dates are rejected', () {
      const state = SandboxWizardState(
        sessionLabel: 'Sessão A',
        contractId: 'ct-1',
      );

      final errors = SandboxWizardValidator.validate(state);
      expect(errors, contains('Informe a data inicial'));
      expect(errors, contains('Informe a data final'));
    });

    test('end before start is rejected', () {
      final state = SandboxWizardState(
        sessionLabel: 'Sessão A',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 3, 1),
        periodEndUtc: DateTime.utc(2026, 2, 1),
      );

      expect(
        SandboxWizardValidator.validate(state),
        contains('A data final deve ser posterior à data inicial'),
      );
    });

    test('complete valid state has no errors', () {
      final state = SandboxWizardState(
        sessionLabel: 'Teste Tolerância 15min',
        contractId: 'ct-1',
        periodStartUtc: DateTime.utc(2026, 1, 1),
        periodEndUtc: DateTime.utc(2026, 3, 1),
        delayToleranceMinutes: 20,
        monthlyPenaltyCapCents: 500000,
        baseFineCents: 15000,
      );

      expect(SandboxWizardValidator.validate(state), isEmpty);
      expect(state.isValid, isTrue);
    });
  });
}
