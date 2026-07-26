import 'package:test/test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';

void main() {
  group('SandboxSimulationResult', () {
    final validUtc = DateTime.utc(2026, 1, 1, 12, 0, 0);

    test('reconstitute constructs object with valid UTC inputs', () {
      final result = SandboxSimulationResult.reconstitute(
        id: 'result-1',
        sessionId: 'session-1',
        organizationId: 'org-1',
        sourceLedgerEntryId: 'ledger-1',
        sourceEventType: 'TICKET_CLOSED',
        occurredAtUtc: validUtc,
        baselineFine: const Money(100),
        baselineRuleSnapshot: const {'rule': 'A'},
        simulatedFine: const Money(50),
        simulatedRuleApplied: const {'rule': 'B'},
        wasOverrideApplied: true,
        baselineCapTruncated: false,
        simulatedCapTruncated: true,
        createdAtUtc: validUtc,
      );

      expect(result.id, 'result-1');
      expect(result.fineDeltaCents, 50);
      expect(result.baselineCapTruncated, isFalse);
      expect(result.simulatedCapTruncated, isTrue);
    });

    test(
      'reconstitute throws DomainException if dates are not UTC (INV-6)',
      () {
        final invalidLocal = DateTime(2026, 1, 1, 12, 0, 0); // Local time

        expect(
          () => SandboxSimulationResult.reconstitute(
            id: 'result-1',
            sessionId: 'session-1',
            organizationId: 'org-1',
            sourceLedgerEntryId: 'ledger-1',
            sourceEventType: 'TICKET_CLOSED',
            occurredAtUtc: invalidLocal, // Throws here
            baselineFine: const Money(100),
            baselineRuleSnapshot: const {},
            simulatedFine: const Money(50),
            simulatedRuleApplied: const {},
            wasOverrideApplied: true,
            createdAtUtc: validUtc,
          ),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('UTC'),
            ),
          ),
        );

        expect(
          () => SandboxSimulationResult.reconstitute(
            id: 'result-1',
            sessionId: 'session-1',
            organizationId: 'org-1',
            sourceLedgerEntryId: 'ledger-1',
            sourceEventType: 'TICKET_CLOSED',
            occurredAtUtc: validUtc,
            baselineFine: const Money(100),
            baselineRuleSnapshot: const {},
            simulatedFine: const Money(50),
            simulatedRuleApplied: const {},
            wasOverrideApplied: true,
            createdAtUtc: invalidLocal, // Throws here
          ),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('UTC'),
            ),
          ),
        );
      },
    );

    test(
      'fromRow parses database fields correctly including JSONB and Money',
      () {
        final row = {
          'id': 'result-db-1',
          'session_id': 'sess-db-1',
          'organization_id': 'org-db-1',
          'source_ledger_entry_id': 'ledger-db-1',
          'source_event_type': 'TICKET_RESOLVED',
          'occurred_at_utc': '2026-01-01T12:00:00Z',
          'baseline_fine_cents': 1500,
          'baseline_rule_snapshot': {'a': 1},
          'simulated_fine_cents': 200,
          'simulated_rule_applied': {'b': 2},
          'was_override_applied': false,
          'baseline_cap_truncated': true,
          'simulated_cap_truncated': false,
          'created_at_utc': '2026-01-01T12:05:00Z',
        };

        final result = SandboxSimulationResult.fromRow(row);

        expect(result.id, 'result-db-1');
        expect(result.occurredAtUtc, DateTime.utc(2026, 1, 1, 12, 0, 0));
        expect(result.baselineFine, const Money(1500)); // Cents to Money
        expect(result.simulatedFine, const Money(200)); // Cents to Money
        expect(result.fineDeltaCents, 1300);
        expect(result.baselineRuleSnapshot, {'a': 1});
        expect(result.wasOverrideApplied, isFalse);
        expect(result.baselineCapTruncated, isTrue);
      },
    );

    test(
      'fromRow handles null jsonb maps and null cap truncated fields safely',
      () {
        final row = {
          'id': 'result-db-1',
          'session_id': 'sess-db-1',
          'organization_id': 'org-db-1',
          'source_ledger_entry_id': 'ledger-db-1',
          'source_event_type': 'TICKET_RESOLVED',
          'occurred_at_utc': '2026-01-01T12:00:00Z',
          'baseline_fine_cents': 1500,
          'baseline_rule_snapshot': null,
          'simulated_fine_cents': 200,
          'simulated_rule_applied': null,
          'was_override_applied': true,
          'baseline_cap_truncated': null,
          'simulated_cap_truncated': null,
          'created_at_utc': '2026-01-01T12:05:00Z',
        };

        final result = SandboxSimulationResult.fromRow(row);
        expect(result.baselineRuleSnapshot, isEmpty);
        expect(result.simulatedRuleApplied, isEmpty);
        expect(result.baselineCapTruncated, isFalse);
        expect(result.simulatedCapTruncated, isFalse);
      },
    );
  });
}
