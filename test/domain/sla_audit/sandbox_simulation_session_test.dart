import 'package:test/test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';

void main() {
  group('SandboxSimulationSession', () {
    final validStart = DateTime.utc(2026, 1, 1);
    final validEnd = DateTime.utc(2026, 2, 1);
    final validUtc = DateTime.utc(2026, 1, 5);

    test('reconstitute constructs valid session', () {
      final session = SandboxSimulationSession.reconstitute(
        id: 'session-1',
        organizationId: 'org-1',
        contractId: 'contract-1',
        sessionLabel: 'My Sim',
        periodStartUtc: validStart,
        periodEndUtc: validEnd,
        overridesSnapshot: const SandboxSimulationOverrides(),
        baselineTotalFines: const Money(1000),
        simulatedTotalFines: const Money(500),
        deltaCents: 500,
        baselineEventCount: 10,
        createdByUserId: 'user-1',
        createdAtUtc: validUtc,
        expiresAtUtc: validUtc.add(const Duration(days: 7)),
      );

      expect(session.id, 'session-1');
      expect(session.isExpired, isFalse); // Because 2026 is current/future
    });

    test('reconstitute throws DomainException if period dates are invalid', () {
      expect(
        () => SandboxSimulationSession.reconstitute(
          id: 'session-1',
          organizationId: 'org-1',
          contractId: 'contract-1',
          sessionLabel: 'My Sim',
          periodStartUtc: validEnd, // Start is after End
          periodEndUtc: validStart,
          overridesSnapshot: const SandboxSimulationOverrides(),
          baselineTotalFines: const Money(1000),
          simulatedTotalFines: const Money(500),
          deltaCents: 500,
          baselineEventCount: 10,
          createdByUserId: 'user-1',
          createdAtUtc: validUtc,
          expiresAtUtc: validUtc.add(const Duration(days: 7)),
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('must be after'),
          ),
        ),
      );
    });

    test(
      'reconstitute throws DomainException if dates are not UTC (INV-6)',
      () {
        final localTime = DateTime(2026, 1, 1);

        expect(
          () => SandboxSimulationSession.reconstitute(
            id: 'session-1',
            organizationId: 'org-1',
            contractId: 'contract-1',
            sessionLabel: 'My Sim',
            periodStartUtc: localTime, // Fails here
            periodEndUtc: validEnd,
            overridesSnapshot: const SandboxSimulationOverrides(),
            baselineTotalFines: const Money(1000),
            simulatedTotalFines: const Money(500),
            deltaCents: 500,
            baselineEventCount: 10,
            createdByUserId: 'user-1',
            createdAtUtc: validUtc,
            expiresAtUtc: validUtc,
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

    test('fromRow parses database fields and Money correctly (INV-4)', () {
      final row = {
        'id': 'sess-db-1',
        'organization_id': 'org-db-1',
        'contract_id': 'cont-db-1',
        'session_label': 'Label',
        'period_start_utc': '2026-01-01T00:00:00Z',
        'period_end_utc': '2026-02-01T00:00:00Z',
        'overrides_snapshot': null,
        'baseline_total_fines_cents': 50000,
        'simulated_total_fines_cents': 20000,
        'delta_cents': 30000,
        'delta_bps': 6000,
        'baseline_event_count': 50,
        'simulated_capped_event_count': 10,
        'created_by_user_id': 'user-db-1',
        'created_at_utc': '2026-01-02T00:00:00Z',
        'expires_at_utc': '2026-01-09T00:00:00Z',
      };

      final session = SandboxSimulationSession.fromRow(row);

      expect(session.id, 'sess-db-1');
      expect(session.baselineTotalFines, const Money(50000));
      expect(session.simulatedTotalFines, const Money(20000));
      expect(session.deltaBps, 6000);
      expect(session.simulatedCappedEventCount, 10);
      expect(session.overridesSnapshot.overrides, isEmpty);
    });

    test('isExpired correctly evaluates past dates', () {
      final session = SandboxSimulationSession.reconstitute(
        id: 'session-1',
        organizationId: 'org-1',
        contractId: 'contract-1',
        sessionLabel: 'My Sim',
        periodStartUtc: validStart,
        periodEndUtc: validEnd,
        overridesSnapshot: const SandboxSimulationOverrides(),
        baselineTotalFines: const Money(1000),
        simulatedTotalFines: const Money(500),
        deltaCents: 500,
        baselineEventCount: 10,
        createdByUserId: 'user-1',
        createdAtUtc: validUtc,
        expiresAtUtc: DateTime.utc(2020, 1, 1), // In the past
      );

      expect(session.isExpired, isTrue);
    });
  });
}
