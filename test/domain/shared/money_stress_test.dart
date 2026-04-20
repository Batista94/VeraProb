import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Financial Stress Test Suite (INV-2, INV-19).
///
/// Validates Symmetric Rounding, BigInt overflow protection,
/// cumulative cap integrity, and WASM-safe boundaries.
void main() {
  group('Financial Stress Test Suite', () {
    // ── T01: Integer Overflow Audit ───────────────────────────────────────
    test('T01: handles 10B BRL x 20000 BPS without 63-bit overflow', () {
      // 10,000,000,000.00 BRL = 10^12 cents
      const hugeAmount = Money(1_000_000_000_000);
      const bps = 20000; // 2.0x multiplier

      // Intermediate: 10^12 x 20000 = 2x10^16 (exceeds int64 max ~9.22x10^18? No, fits)
      // BigInt handles it safely regardless.
      final result = hugeAmount.multiplyByBps(bps);

      // Expected: (10^12 * 20000) / 10000 = 2x10^12 cents = 20B BRL
      expect(result.cents, equals(2_000_000_000_000));
    });

    test('T01b: handles near-int64-limit values safely', () {
      // 9x10^17 cents (close to int64 max / 10000)
      const massive = Money(900_000_000_000_000_000);
      const bps = 10000; // 1.0x — should return same value

      final result = massive.multiplyByBps(bps);
      expect(result.cents, equals(900_000_000_000_000_000));
    });

    // ── T02: Rounding vs. Truncating Proof ────────────────────────────────
    test('T02: proves cumulative drift with 2.00 BRL x 3333 BPS over 1M txns', () {
      const transactionCount = 1_000_000;
      const twoBrl = Money(200); // 2,00 BRL
      const penaltyBps = 3333; // ~1/3 penalty

      // Per-transaction calculation:
      // Truncated: (200 * 3333) ~/ 10000 = 666600 ~/ 10000 = 66 cents
      // Rounded:   (200 * 3333 + 5000) ~/ 10000 = 671600 ~/ 10000 = 67 cents
      // Drift per txn: 1 cent

      final roundedTotal = twoBrl.multiplyByBps(penaltyBps);
      const truncatedPerTxn = (200 * 3333) ~/ 10000;

      expect(roundedTotal.cents, equals(67));
      expect(truncatedPerTxn, equals(66));

      // Cumulative over 1M transactions
      const cumulativeRounded = 67 * transactionCount;
      const cumulativeTruncated = 66 * transactionCount;
      const driftCents = cumulativeRounded - cumulativeTruncated;

      // Drift = 1,000,000 cents = R$ 10,000.00
      expect(driftCents, equals(1_000_000));
      expect(driftCents / 100.0, equals(10000.0)); // R$ 10,000.00

      // Log proof for audit trail
      // ignore: avoid_print
      print(
        'T02 DRIFT PROOF:\n'
        '  Truncated/txn: $truncatedPerTxn cents\n'
        '  Rounded/txn:   ${roundedTotal.cents} cents\n'
        '  Cumulative truncated: $cumulativeTruncated cents (R\$ ${cumulativeTruncated / 100})\n'
        '  Cumulative rounded:   $cumulativeRounded cents (R\$ ${cumulativeRounded / 100})\n'
        '  Drift: $driftCents cents (R\$ ${driftCents / 100})',
      );
    });

    // ── T03: Cumulative Cap Integrity ─────────────────────────────────────
    //
    // ROUNDING DRIFT POLICY (INV-7: Immutable Ledger):
    // Each ledger entry is an atomic, sealed fact. We round per-entry (Half
    // Away From Zero), not cumulatively. This guarantees forensic replay:
    // reprocessing entry #437 in isolation yields the exact same cent value.
    //
    // The trade-off: the "Sum of Parts" may drift from the "Whole Calculation"
    // by at most ±0.5 cents per entry. This is accepted as inherent rounding
    // margin of the Sealed Truth — documented, bounded, and auditable.
    //
    //   drift_maximo = num_entries × 0.5 cents
    //
    // The cap operates on rounded values — it is the "Verdade Selada".
    // Residual drift is a footnote, not a failure.
    // ──────────────────────────────────────────────────────────────────────
    test('T03: accumulated penalty locks exactly at cap of 5000.00 BRL', () {
      const cap = Money(500_000); // 5,000.00 BRL
      const basePenaltyBrl = Money(501); // 5.01 BRL per penalty
      const penaltyBps = 10000; // 1.0x — exact, no rounding
      const numPenalties = 1000;

      int effectivePenalty = 0;
      int sumOfParts = 0;

      for (int i = 0; i < numPenalties; i++) {
        final singlePenalty = basePenaltyBrl.multiplyByBps(penaltyBps).cents;
        sumOfParts += singlePenalty;
        final projected = effectivePenalty + singlePenalty;
        effectivePenalty = projected < cap.cents ? projected : cap.cents;
      }

      // Exact BPS: no rounding occurred → Sum of Parts = raw sum
      expect(sumOfParts, equals(501_000));
      expect(effectivePenalty, equals(cap.cents)); // capped at 500,000
    });

    test('T03b: cap with fractional BPS — documents drift bound', () {
      const cap = Money(500_000); // 5,000.00 BRL
      // Each entry: 5000 cents × 10001 BPS = 50,005,000 → raw = 5000.5 cents
      // Rounded (Half Away From Zero): 5001 cents (+0.5 drift per entry)
      const baseValue = Money(5000); // 50.00 BRL base
      const fractionalBps = 10001; // 1.0001x → raw = 5000.5 → rounds to 5001
      const numPenalties = 100;

      int effectivePenalty = 0;
      int sumOfParts = 0;
      BigInt sumOfRawMilliCents = BigInt.zero;

      for (int i = 0; i < numPenalties; i++) {
        final singlePenalty = baseValue.multiplyByBps(fractionalBps).cents;
        sumOfParts += singlePenalty;

        // Raw millicents: exact value before rounding
        final rawMilli =
            (BigInt.from(baseValue.cents) *
                BigInt.from(fractionalBps) *
                BigInt.from(1000)) ~/
            BigInt.from(10000);
        sumOfRawMilliCents += rawMilli;

        final projected = effectivePenalty + singlePenalty;
        effectivePenalty = projected < cap.cents ? projected : cap.cents;
      }

      // Each entry rounds 5000.5 → 5001 (+0.5 drift)
      // Sum of parts: 5001 × 100 = 500,100
      expect(sumOfParts, equals(500_100));

      // Sum of raw: 5000.5 × 100 = 500,050 cents
      final sumOfRawCents = (sumOfRawMilliCents ~/ BigInt.from(1000)).toInt();
      expect(sumOfRawCents, equals(500_050));

      // Rounding drift: difference between rounded sum and raw sum
      final roundingDrift = sumOfParts - sumOfRawCents;
      final maxDriftCents = (numPenalties * 0.5).round();

      expect(
        roundingDrift,
        lessThanOrEqualTo(maxDriftCents),
        reason:
            'Rounding drift ($roundingDrift cents) exceeds maximum '
            'acceptable bound ($maxDriftCents cents = $numPenalties × 0.5)',
      );
      expect(roundingDrift, equals(maxDriftCents)); // exactly at bound

      // Cap seals at exactly 500,000 — the Verdade Selada
      expect(effectivePenalty, equals(cap.cents));

      // ignore: avoid_print
      print(
        'T03b CAP + DRIFT:\n'
        '  Per entry raw: 5000.5 → rounds to 5001 (+0.5 cents)\n'
        '  Sum of rounded parts: $sumOfParts cents (R\$ ${sumOfParts / 100})\n'
        '  Sum of raw values:    $sumOfRawCents cents (R\$ ${sumOfRawCents / 100})\n'
        '  Rounding drift: $roundingDrift cents | Max bound: $maxDriftCents cents ✅\n'
        '  Cap sealed: $effectivePenalty cents (R\$ ${effectivePenalty / 100})',
      );
    });

    test('T03c: worst-case drift stress — every entry rounds +0.5', () {
      // Worst case: each BPS calculation lands exactly on X.5,
      // rounding up by 0.5 cents every time.
      // We prove: even at worst, drift ≤ numEntries × 0.5 cents.
      //
      // 100 cents × 10050 BPS = 1,005,000 → 1,005,000 ~/ 10000 = 100 remainder 5000
      // Raw: 100.5 cents → rounds to 101 cents (+0.5 drift each)

      const baseValue = Money(100); // 1.00 BRL
      const bps = 10050; // 1.005x → raw = 100.5 cents
      const numEntries = 10_000; // 10k entries → max drift = 5,000 cents

      int totalRounded = 0;
      BigInt totalRawMilliCents = BigInt.zero;

      for (int i = 0; i < numEntries; i++) {
        final rounded = baseValue.multiplyByBps(bps).cents;
        totalRounded += rounded;

        // Raw millicents: (100 * 10050 * 1000) / 10000 = 100,500 millicents = 100.5 cents
        final rawMilli =
            (BigInt.from(100) * BigInt.from(10050) * BigInt.from(1000)) ~/
            BigInt.from(10000);
        totalRawMilliCents += rawMilli;
      }

      // Total rounded: 101 × 10000 = 1,010,000 cents
      expect(totalRounded, equals(1_010_000));

      // Total raw: 100.5 × 10000 = 1,005,000 cents
      final totalRawCents = (totalRawMilliCents ~/ BigInt.from(1000)).toInt();
      expect(totalRawCents, equals(1_005_000));

      // Drift: 1,010,000 - 1,005,000 = 5,000 cents = R$ 50.00
      final driftCents = totalRounded - totalRawCents;
      final maxAcceptableDrift = (numEntries * 0.5).round();

      expect(driftCents, equals(maxAcceptableDrift)); // exactly at bound
      expect(driftCents, lessThanOrEqualTo(maxAcceptableDrift));

      // ignore: avoid_print
      print(
        '\nT03c WORST-CASE DRIFT:\n'
        '  Entries: $numEntries\n'
        '  Rounded total: $totalRounded cents (R\$ ${totalRounded / 100})\n'
        '  Raw total:     $totalRawCents cents (R\$ ${totalRawCents / 100})\n'
        '  Drift:         $driftCents cents (R\$ ${driftCents / 100})\n'
        '  Max bound:     $maxAcceptableDrift cents (R\$ ${maxAcceptableDrift / 100})\n'
        '  Status: WITHIN BOUND ✅',
      );
    });

    // ── T03d: Cap Clipping Auditability (The "Clipping" Problem) ──────────
    //
    // SCENARIO: Cap remaining space is R$ 0.02, but next BPS calculation
    // rounds to R$ 0.04. The Cap clips to R$ 0.02 — the math "doesn't match."
    //
    // SOLUTION: The Ledger records both the rounded value (gross) and the
    // capped value (final), with a `capApplied` flag. This ensures forensic
    // auditability: an auditor sees that the Cap clipped, not a bug.
    //
    // Chain: Raw BPS → Symmetric Rounding → Gross → Cap Apply → Final
    // ──────────────────────────────────────────────────────────────────────
    test('T03d: cap clipping at boundary — audit trail preserved', () {
      // Scenario: 5000 cents × 3 BPS = 15000 + 5000 = 20000 ~/ 10000 = 2 cents
      // Cap = 5 cents. After 2 entries: 2 × 2 = 4 (1 cent remaining).
      // Entry #3: rounds to 2 cents, but only 1 cent remains → clips to 1.
      // Entries #4-5: cap is full → clips to 0.

      const smallBase = Money(5000); // R$ 50.00
      const smallBps = 3; // 0.03% → raw = 1.5 cents → rounds to 2 cents
      const smallCap = Money(5); // R$ 0.05 cap

      final List<Map<String, int>> ledgerEntries = [];
      int accumulated = 0;

      for (int i = 0; i < 5; i++) {
        final grossCents = smallBase.multiplyByBps(smallBps).cents;
        final remainingCap = smallCap.cents - accumulated;
        final finalCents = grossCents < remainingCap
            ? grossCents
            : remainingCap.clamp(0, remainingCap);
        final capApplied = grossCents > remainingCap;

        accumulated += finalCents;

        ledgerEntries.add({
          'entry': i + 1,
          'gross': grossCents,
          'final': finalCents,
          'capApplied': capApplied ? 1 : 0,
          'remainingAfter': smallCap.cents - accumulated,
        });
      }

      // Verify each entry
      expect(
        ledgerEntries[0]['gross'],
        equals(2),
      ); // 5000*3=15000+5000=20000/10000=2
      expect(ledgerEntries[0]['final'], equals(2));
      expect(ledgerEntries[0]['capApplied'], equals(0));

      expect(ledgerEntries[1]['gross'], equals(2));
      expect(ledgerEntries[1]['final'], equals(2));
      expect(ledgerEntries[1]['capApplied'], equals(0));

      // Entry #3: gross=2, remaining=1 → clips to 1, capApplied=true
      expect(ledgerEntries[2]['gross'], equals(2));
      expect(ledgerEntries[2]['final'], equals(1)); // CLIPPED!
      expect(ledgerEntries[2]['capApplied'], equals(1));

      // Entries #4-5: cap is full, everything clips to 0
      expect(ledgerEntries[3]['gross'], equals(2));
      expect(ledgerEntries[3]['final'], equals(0));
      expect(ledgerEntries[3]['capApplied'], equals(1));

      expect(ledgerEntries[4]['gross'], equals(2));
      expect(ledgerEntries[4]['final'], equals(0));
      expect(ledgerEntries[4]['capApplied'], equals(1));

      // Accumulated = 2 + 2 + 1 + 0 + 0 = 5 = exact cap
      expect(accumulated, equals(smallCap.cents));

      // ignore: avoid_print
      print(
        '\nT03d CAP CLIPPING AUDIT TRAIL:\n'
        '  Cap: R\$ ${smallCap.cents / 100} | Per entry BPS: ${smallBase.cents} × $smallBps\n'
        '  Entry | Gross | Final | CapApplied | Remaining After\n'
        '  ------|-------|-------|------------|----------------',
      );
      for (final entry in ledgerEntries) {
        // ignore: avoid_print
        print(
          '  #${entry['entry']}    | ${entry['gross']}¢    | ${entry['final']}¢    '
          '| ${entry['capApplied'] == 1 ? 'YES       ' : 'NO        '}'
          '| ${entry['remainingAfter']}¢',
        );
      }
      // ignore: avoid_print
      print(
        '  Accumulated: $accumulated cents (R\$ ${accumulated / 100}) = Cap ✅\n'
        '  Entry #3 proves: gross=2¢ ≠ final=1¢ → capApplied=YES → audit trail intact',
      );
    });

    // ── T04: WASM Safe Boundary ───────────────────────────────────────────
    test('T04: values near 2^53-1 maintain penny precision in WASM', () {
      // 2^53 - 1 = 9,007,199,254,740,991 (Number.MAX_SAFE_INTEGER)
      // In cents: ~90 trillion BRL — way beyond any real value,
      // but we test the boundary for WASM double-safety.
      const maxSafeCents = 9_007_199_254_740_991;
      const nearMax = Money(maxSafeCents);

      // Identity at 1.0x
      final identity = nearMax.multiplyByBps(10000);
      expect(identity.cents, equals(maxSafeCents));

      // Double at 2.0x
      final doubled = nearMax.multiplyByBps(20000);
      expect(doubled.cents, equals(maxSafeCents * 2));

      // Half at 5000 BPS (0.5x)
      final halved = nearMax.multiplyByBps(5000);
      // With rounding: (maxSafeCents * 5000 + 5000) ~/ 10000
      final expected =
          (BigInt.from(maxSafeCents) * BigInt.from(5000) + BigInt.from(5000)) ~/
          BigInt.from(10000);
      expect(halved.cents, equals(expected.toInt()));

      // Verify .toDouble() doesn't degrade value at this boundary
      // (Bridge conversion — Double Required by annotation standard)
      final asDouble = nearMax.toDouble();
      expect(asDouble, equals(maxSafeCents / 100.0));
    });

    test('T04b: symmetric rounding produces deterministic results at boundaries', () {
      // Test edge cases around rounding thresholds
      const oneCent = Money(1);

      // 1 cent x 4999 BPS (0.4999x) = 4999 + 5000 = 9999 ~/ 10000 = 0 cents (rounds down)
      final justBelowHalf = oneCent.multiplyByBps(4999);
      expect(justBelowHalf.cents, equals(0));

      // 1 cent x 5000 BPS (0.5x) = 5000 + 5000 = 10000 ~/ 10000 = 1 cent — rounds UP
      final halfBps = oneCent.multiplyByBps(5000);
      expect(halfBps.cents, equals(1));

      // 1 cent x 15000 BPS (1.5x) = 15000 + 5000 = 20000 ~/ 10000 = 2 cents — rounds up from 1.5
      final onePointFive = oneCent.multiplyByBps(15000);
      expect(onePointFive.cents, equals(2));

      // 1 cent x 14999 BPS (1.4999x) = 14999 + 5000 = 19999 ~/ 10000 = 1 cent — rounds down
      final justBelow = oneCent.multiplyByBps(14999);
      expect(justBelow.cents, equals(1));
    });
  });

  // ── Regression: Symmetric Rounding vs. Truncation table ────────────────
  group('Symmetric Rounding audit table', () {
    test('documents rounding behavior for common BPS values', () {
      // For 1 cent base, show what each BPS produces
      // ignore: avoid_print
      print('\nROUNDING AUDIT TABLE (base=1 cent):');
      // ignore: avoid_print
      print('BPS    | Truncated | Rounded | Delta');
      for (final bps in [3333, 5000, 7500, 10000, 15000, 17500, 20000]) {
        final truncated = (1 * bps) ~/ 10000;
        final rounded = const Money(1).multiplyByBps(bps).cents;
        final delta = rounded - truncated;
        // ignore: avoid_print
        print(
          '$bps | $truncated      | $rounded     | ${delta > 0 ? "+$delta" : delta}',
        );
      }
    });
  });
}
