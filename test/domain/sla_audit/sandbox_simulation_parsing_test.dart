import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_delta.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';

/// INV-4 / INV-6 deserialization guards for SLA Sandbox shadow-ledger rows.
void main() {
  group('SandboxSimulationResult.fromRow — INV-4 / INV-6', () {
    final row = <String, dynamic>{
      'id': 'res-1',
      'session_id': 'sess-1',
      'organization_id': 'org-1',
      'source_ledger_entry_id': 'ledger-1',
      'source_event_type': 'SANCTION_RECOMMENDED',
      'occurred_at_utc': '2026-03-15T14:30:00Z',
      'baseline_fine_cents': 15000,
      'baseline_rule_snapshot': {'threshold_minutes': 15},
      'simulated_fine_cents': 12750,
      'simulated_rule_applied': {'threshold_minutes': 20},
      'was_override_applied': true,
      'baseline_cap_truncated': false,
      'simulated_cap_truncated': true,
      'created_at_utc': '2026-06-01T12:00:00+00:00',
    };

    test('parses monetary fields strictly as int cents (INV-4)', () {
      final result = SandboxSimulationResult.fromRow(row);

      expect(result.baselineFine, isA<Money>());
      expect(result.baselineFine.cents, isA<int>());
      expect(result.baselineFine.cents, 15000);
      expect(result.simulatedFine.cents, isA<int>());
      expect(result.simulatedFine.cents, 12750);
      expect(result.fineDeltaCents, isA<int>());
      expect(result.fineDeltaCents, 2250);
    });

    test(
      'coerces JSON num (double wire) to int cents without precision loss',
      () {
        final wired = Map<String, dynamic>.from(row)
          ..['baseline_fine_cents'] = 15000.0
          ..['simulated_fine_cents'] = 12750.0;

        final result = SandboxSimulationResult.fromRow(wired);
        expect(result.baselineFine.cents, 15000);
        expect(result.simulatedFine.cents, 12750);
        expect(result.baselineFine.cents.runtimeType, int);
      },
    );

    test('interprets occurred_at_utc and created_at_utc as UTC (INV-6)', () {
      final result = SandboxSimulationResult.fromRow(row);

      expect(result.occurredAtUtc.isUtc, isTrue);
      expect(result.createdAtUtc.isUtc, isTrue);
      expect(result.occurredAtUtc, DateTime.utc(2026, 3, 15, 14, 30));
      expect(result.createdAtUtc, DateTime.utc(2026, 6, 1, 12));
    });

    test('naive Postgres timestamp without Z is treated as UTC (INV-6)', () {
      final naive = Map<String, dynamic>.from(row)
        ..['occurred_at_utc'] = '2026-01-01T00:00:00'
        ..['created_at_utc'] = '2026-01-02T18:45:30.123456';

      final result = SandboxSimulationResult.fromRow(naive);
      expect(result.occurredAtUtc.isUtc, isTrue);
      expect(result.occurredAtUtc, DateTime.utc(2026, 1, 1));
      expect(result.createdAtUtc.isUtc, isTrue);
      expect(result.createdAtUtc.hour, 18);
      expect(result.createdAtUtc.minute, 45);
    });

    test('reconstitute rejects non-UTC DateTime (INV-6 fail-closed)', () {
      expect(
        () => SandboxSimulationResult.reconstitute(
          id: 'r',
          sessionId: 's',
          organizationId: 'o',
          sourceLedgerEntryId: 'l',
          sourceEventType: 'NO_SHOW_PENALTY',
          occurredAtUtc: DateTime(2026, 1, 1), // local / non-UTC
          baselineFine: const Money(100),
          baselineRuleSnapshot: const {},
          simulatedFine: const Money(90),
          simulatedRuleApplied: const {},
          wasOverrideApplied: false,
          createdAtUtc: DateTime.utc(2026, 1, 2),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('SandboxSimulationSession + Delta — INV-4 / INV-6', () {
    final sessionRow = <String, dynamic>{
      'id': 'sess-1',
      'organization_id': 'org-1',
      'contract_id': 'ct-0042',
      'session_label': 'Teste Tolerância 15min',
      'period_start_utc': '2026-01-01T00:00:00Z',
      'period_end_utc': '2026-06-30T23:59:59Z',
      'overrides_snapshot': {
        'overrides': [
          {
            'rule_type': 'MAX_TOLERANCE_DELAY',
            'rule_config': {'threshold_minutes': 20},
          },
        ],
        'financial_overrides': {
          'monthly_penalty_cap_cents': 500000,
          'base_fine_cents': 15000,
        },
      },
      'baseline_total_fines_cents': 8420000,
      'simulated_total_fines_cents': 7157000,
      'delta_cents': 1263000,
      'delta_bps': -1500,
      'baseline_event_count': 847,
      'simulated_capped_event_count': 18,
      'created_by_user_id': 'user-1',
      'created_at_utc': '2026-07-01T10:00:00Z',
      'expires_at_utc': '2026-07-31T10:00:00Z',
    };

    test('parses aggregate fines and delta as int cents (INV-4)', () {
      final session = SandboxSimulationSession.fromRow(sessionRow);

      expect(session.baselineTotalFines.cents, isA<int>());
      expect(session.baselineTotalFines.cents, 8420000);
      expect(session.simulatedTotalFines.cents, isA<int>());
      expect(session.simulatedTotalFines.cents, 7157000);
      expect(session.deltaCents, isA<int>());
      expect(session.deltaCents, 1263000);
      expect(session.deltaBps, isA<int?>());
      expect(session.deltaBps, -1500);

      expect(session.direction, SandboxDeltaDirection.savings);
      expect(session.deltaAmount.cents, 1263000);
    });

    test('financial_overrides base_fine_cents / cap parse as int (INV-4)', () {
      final session = SandboxSimulationSession.fromRow(sessionRow);
      final financial = session.overridesSnapshot.financialOverrides!;

      expect(financial.baseFineCents, isA<int?>());
      expect(financial.baseFineCents, 15000);
      expect(financial.monthlyPenaltyCapCents, isA<int?>());
      expect(financial.monthlyPenaltyCapCents, 500000);
    });

    test('period and provenance timestamps are UTC (INV-6)', () {
      final session = SandboxSimulationSession.fromRow(sessionRow);

      expect(session.periodStartUtc.isUtc, isTrue);
      expect(session.periodEndUtc.isUtc, isTrue);
      expect(session.createdAtUtc.isUtc, isTrue);
      expect(session.expiresAtUtc.isUtc, isTrue);
      expect(session.periodStartUtc, DateTime.utc(2026, 1, 1));
      expect(session.periodEndUtc, DateTime.utc(2026, 6, 30, 23, 59, 59));
    });

    test('wire doubles for aggregate cents keep integer precision', () {
      final wired = Map<String, dynamic>.from(sessionRow)
        ..['baseline_total_fines_cents'] = 8420000.0
        ..['simulated_total_fines_cents'] = 7157000.0
        ..['delta_cents'] = 1263000.0;

      final session = SandboxSimulationSession.fromRow(wired);
      expect(session.baselineTotalFines.cents, 8420000);
      expect(session.deltaCents, 1263000);
    });

    test('negative delta_cents maps to increase direction', () {
      final worse = Map<String, dynamic>.from(sessionRow)
        ..['simulated_total_fines_cents'] = 9000000
        ..['delta_cents'] = -580000;

      final session = SandboxSimulationSession.fromRow(worse);
      expect(session.direction, SandboxDeltaDirection.increase);
      expect(session.deltaAmount.cents, 580000);
    });
  });

  group('SandboxSimulationOverrides — adversarial financial input', () {
    test('fromJson coerces base_fine_cents from num to int', () {
      final overrides = SandboxSimulationOverrides.fromJson({
        'overrides': <Map<String, dynamic>>[],
        'financial_overrides': {
          'base_fine_cents': 15000.0,
          'monthly_penalty_cap_cents': 500000.0,
        },
      });

      expect(overrides.financialOverrides!.baseFineCents, isA<int?>());
      expect(overrides.financialOverrides!.baseFineCents, 15000);
      expect(overrides.financialOverrides!.monthlyPenaltyCapCents, 500000);
    });

    test('validate rejects negative base_fine_cents', () {
      const overrides = SandboxSimulationOverrides(
        financialOverrides: SandboxFinancialOverrides(baseFineCents: -1),
      );
      expect(overrides.validate, throwsA(isA<DomainException>()));
    });

    test('validate rejects empty rule_config (malicious empty override)', () {
      const overrides = SandboxSimulationOverrides(
        overrides: [
          SandboxRuleOverride(
            ruleType: SlaRuleType.maxToleranceDelay,
            ruleConfig: {},
          ),
        ],
      );
      expect(overrides.validate, throwsA(isA<DomainException>()));
    });

    test('toJson round-trip preserves int cents', () {
      const original = SandboxSimulationOverrides(
        financialOverrides: SandboxFinancialOverrides(
          baseFineCents: 15000,
          monthlyPenaltyCapCents: 500000,
        ),
      );
      final restored = SandboxSimulationOverrides.fromJson(original.toJson());
      expect(restored.financialOverrides!.baseFineCents, 15000);
      expect(restored.financialOverrides!.monthlyPenaltyCapCents, 500000);
    });
  });
}
