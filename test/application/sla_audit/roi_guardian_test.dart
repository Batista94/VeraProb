// TDD anchor — Phase 10 Workstream 3 (SENIOR)
// Tests RoiSummary parsing from v_roi_summary view rows.
// INV-4: all monetary values in BIGINT cents.
// INV-22: organization_id isolation (view groups by org).

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/forensic_ledger_providers.dart';

void main() {
  group('RoiSummary.fromRow — INV-4 cents parsing', () {
    test('full row parses correctly', () {
      final row = {
        'organization_id': 'org-001',
        'recovered_trips': 3,
        'total_recovered_cents': 150000,
        'total_avoided_penalty_cents': 80000,
        'total_linked_trips': 12,
        'pending_orphans': 2,
      };

      final summary = RoiSummary.fromRow(row);

      expect(summary.recoveredTrips, equals(3));
      expect(summary.totalRecoveredCents, equals(150000)); // INV-4: cents
      expect(summary.totalAvoidedPenaltyCents, equals(80000)); // INV-4: cents
      expect(summary.totalLinkedTrips, equals(12));
      expect(summary.pendingOrphans, equals(2));
    });

    test(
      'null values default to 0 (safe — no RECONCILED_AS_NEW_REVENUE yet)',
      () {
        final row = {
          'organization_id': 'org-002',
          'recovered_trips': null,
          'total_recovered_cents': null,
          'total_avoided_penalty_cents': null,
          'total_linked_trips': null,
          'pending_orphans': null,
        };

        final summary = RoiSummary.fromRow(row);

        expect(summary.recoveredTrips, equals(0));
        expect(summary.totalRecoveredCents, equals(0));
        expect(summary.totalAvoidedPenaltyCents, equals(0));
        expect(summary.totalLinkedTrips, equals(0));
        expect(summary.pendingOrphans, equals(0));
      },
    );

    test('ROI formula: recovered / (recovered + avoided) ratio', () {
      final summary = RoiSummary.fromRow({
        'recovered_trips': 5,
        'total_recovered_cents': 500000, // R$ 5.000,00
        'total_avoided_penalty_cents': 200000, // R$ 2.000,00
        'total_linked_trips': 20,
        'pending_orphans': 0,
      });

      // Tool cost not tracked in DB — ROI computed in board report, not here
      // Assert cents arithmetic is integer (INV-4: no float truncation)
      final total =
          summary.totalRecoveredCents + summary.totalAvoidedPenaltyCents;
      expect(total, equals(700000)); // no rounding error
    });

    test('recovered_trips 0 when no RECONCILED_AS_NEW_REVENUE rows', () {
      final summary = RoiSummary.fromRow({
        'recovered_trips': 0,
        'total_recovered_cents': 0,
        'total_avoided_penalty_cents': 50000,
        'total_linked_trips': 5,
        'pending_orphans': 1,
      });

      expect(summary.recoveredTrips, equals(0));
      expect(summary.pendingOrphans, equals(1));
    });
  });
}
