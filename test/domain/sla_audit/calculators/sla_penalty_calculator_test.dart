import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/calculators/sla_penalty_calculator.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sla_calculation_exception.dart';

void main() {
  group('SlaPenaltyCalculator', () {
    late SlaPenaltyCalculator calculator;

    setUp(() {
      calculator = const SlaPenaltyCalculator();
    });

    // ── Helper: Create a contract with base penalty ───────────────────────

    Contract createContract({
      required int baseCents,
      int penaltyMultiplierBps = 10000,
    }) {
      return Contract.create(
        organizationId: 'org-123',
        name: 'Test Contract',
        contractorName: 'Test Contractor',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
        nowUtc: DateTime.utc(2026, 4, 15),
        financialCeiling: Money(baseCents),
        penaltyMultiplierBps: penaltyMultiplierBps,
      );
    }

    // ── TIER STEP FUNCTION TESTS ──────────────────────────────────────────

    group('Tier Step Function', () {
      test('T01: 899s (<15min) → No Penalty (0 BPS)', () {
        final contract = createContract(baseCents: 150000);
        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 899),
        );

        expect(result.appliedTier, 'No Penalty');
        expect(result.penalty.cents, 0);
      });

      test('T01: 900s (≥15min) → Tier 1 (500 BPS)', () {
        final contract = createContract(baseCents: 150000);
        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900),
        );

        expect(result.appliedTier, 'Tier 1');
        // 150000 × 500 BPS = 75000000 + 5000 = 75005000 ~/ 10000 = 7500 cents
        expect(result.penalty.cents, 7500);
      });

      test('T02: 1799s (15-29min) → Tier 1 (500 BPS)', () {
        final contract = createContract(baseCents: 150000);
        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 1799),
        );

        expect(result.appliedTier, 'Tier 1');
        expect(result.penalty.cents, 7500);
      });

      test('T02: 1800s (≥30min) → Tier 2 (1200 BPS)', () {
        final contract = createContract(baseCents: 150000);
        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 1800),
        );

        expect(result.appliedTier, 'Tier 2');
        // 150000 × 1200 BPS = 180000000 + 5000 = 180005000 ~/ 10000 = 18000 cents
        expect(result.penalty.cents, 18000);
      });

      test('Boundary: 14m59s = 899s → No Penalty', () {
        final contract = createContract(baseCents: 150000);
        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(minutes: 14, seconds: 59),
        );

        expect(result.appliedTier, 'No Penalty');
        expect(result.penalty.cents, 0);
      });

      test('Boundary: 15m01s = 901s → Tier 1', () {
        final contract = createContract(baseCents: 150000);
        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(minutes: 15, seconds: 1),
        );

        expect(result.appliedTier, 'Tier 1');
        expect(result.penalty.cents, 7500);
      });
    });

    // ── PENALTY COMPOSITION TESTS ─────────────────────────────────────────

    group('Penalty Composition', () {
      test('T03: Base 150000 + 500 BPS + 5000 fixed = 12500 cents', () {
        final contract = createContract(baseCents: 150000);
        const fixedPenalty = Money(5000); // R$ 50.00

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900), // Tier 1
          fixedPenalty: fixedPenalty,
        );

        // Tier amount: 150000 × 500 BPS = 7500 cents
        // Fixed: 5000 cents
        // Total: 7500 + 5000 = 12500 cents (R$ 125.00)
        expect(result.penalty.cents, 12500);
        expect(result.appliedTier, 'Tier 1');
      });

      test('T03: Base 150000 + 1200 BPS + 5000 fixed = 23000 cents', () {
        final contract = createContract(baseCents: 150000);
        const fixedPenalty = Money(5000); // R$ 50.00

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 1800), // Tier 2
          fixedPenalty: fixedPenalty,
        );

        // Tier amount: 150000 × 1200 BPS = 18000 cents
        // Fixed: 5000 cents
        // Total: 18000 + 5000 = 23000 cents (R$ 230.00)
        expect(result.penalty.cents, 23000);
        expect(result.appliedTier, 'Tier 2');
      });

      test('Without fixed penalty: Base 150000 + 500 BPS = 7500 cents', () {
        final contract = createContract(baseCents: 150000);

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900), // Tier 1
        );

        expect(result.penalty.cents, 7500);
        expect(result.appliedTier, 'Tier 1');
      });
    });

    // ── NON-NEGATIVE GUARD TESTS ──────────────────────────────────────────

    group('Non-Negative Guard', () {
      test('T04: Negative delay (-60s) → const Money(0), never negative', () {
        final contract = createContract(baseCents: 150000);

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: -60), // Early delivery
        );

        expect(result.penalty.cents, 0);
        expect(result.appliedTier, 'No Penalty');
      });

      test('T04: Zero delay → const Money(0)', () {
        final contract = createContract(baseCents: 150000);

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 0),
        );

        expect(result.penalty.cents, 0);
        expect(result.appliedTier, 'No Penalty');
      });
    });

    // ── NULL/INVALID CONTRACT VALIDATION TESTS ────────────────────────────

    group('Null/Invalid Contract Validation', () {
      test(
        'T05: Contract without financialCeiling → SlaCalculationException',
        () {
          final contractWithoutCeiling = Contract.create(
            organizationId: 'org-123',
            name: 'Test Contract',
            contractorName: 'Test Contractor',
            validFromUtc: DateTime.utc(2026, 1, 1),
            validUntilUtc: DateTime.utc(2026, 12, 31),
            nowUtc: DateTime.utc(2026, 4, 15),
            financialCeiling: null, // No ceiling
          );

          expect(
            () => calculator.calculate(
              contract: contractWithoutCeiling,
              delay: const Duration(seconds: 900),
            ),
            throwsA(isA<SlaCalculationException>()),
          );
        },
      );
    });

    // ── VALUE OBJECT TESTS ────────────────────────────────────────────────

    group('SlaPenalty Value Object', () {
      test('Equatable: Two identical penalties are equal', () {
        final contract = createContract(baseCents: 150000);

        final result1 = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900),
        );

        final result2 = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900),
        );

        expect(result1, equals(result2));
        expect(result1.hashCode, equals(result2.hashCode));
      });

      test('Penalty is Money object with correct cents', () {
        final contract = createContract(baseCents: 150000);

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900),
        );

        expect(result.penalty, isA<Money>());
        expect(result.penalty.cents, 7500);
      });

      test('Applied tier is descriptive string', () {
        final contract = createContract(baseCents: 150000);

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900),
        );

        expect(result.appliedTier, isNotEmpty);
        expect(result.appliedTier, 'Tier 1');
      });
    });

    // ── SYMMETRIC ROUNDING PROOF ──────────────────────────────────────────

    group('Symmetric Rounding (Half Away From Zero)', () {
      test('Positive drift rounds away from zero', () {
        // 10 seconds × 1500 BPS = 15000 + 5000 = 20000 ~/ 10000 = 2 seconds
        // Without rounding: 15000 ~/ 10000 = 1 second (truncated)
        final contract = createContract(baseCents: 10);

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900),
        );

        // 10 × 500 = 5000 + 5000 = 10000 ~/ 10000 = 1 cent
        expect(result.penalty.cents, 1);
      });

      test('Large base maintains precision', () {
        // 150000 × 500 = 75000000 + 5000 = 75005000 ~/ 10000 = 7500 cents
        final contract = createContract(baseCents: 150000);

        final result = calculator.calculate(
          contract: contract,
          delay: const Duration(seconds: 900),
        );

        expect(result.penalty.cents, 7500);
      });
    });
  });
}
