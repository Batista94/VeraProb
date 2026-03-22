import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';

void main() {
  group('SlaLedgerMapper - EvidenceEvents Verification', () {
    final DateTime now = DateTime.now().toUtc();

    test(
      'OccurrenceRegisteredEvidence maps gracefully without validation faults',
      () {
        final evidence = OccurrenceRegisteredEvidence(
          organizationId: 'org-1',
          occurredAtUtc: now,
          tripId: 'trip-789',
          vehicleId: 'veh-001',
          operatorId: 'operator-ab',
          occurrenceType: 'Acidente',
          notes: 'Colisão lateral',
          metadata: {'severity': 'high'},
        );

        final entry = SlaLedgerMapper.mapToEntry(evidence);

        expect(entry.type, 'OCCURRENCE_REGISTERED');
        expect(entry.setId, 'trip-789');
        expect(entry.contractId, 'N/A');
        expect(entry.planVersion, 0);
        expect(entry.occurredAtUtc, now);

        expect(entry.payload['vehicle_id'], 'veh-001');
        expect(entry.payload['operator_id'], 'operator-ab');
        expect(entry.payload['occurrence_type'], 'Acidente');
        expect(entry.payload['notes'], 'Colisão lateral');
        expect(entry.payload['metadata'], {'severity': 'high'});
      },
    );

    test('TripInterruptedEvidence maps gracefully', () {
      final evidence = TripInterruptedEvidence(
        organizationId: 'org-1',
        occurredAtUtc: now,
        tripId: 'trip-789',
        vehicleId: 'veh-001',
        operatorId: 'operator-cd',
        reason: 'Pneu Furado',
      );

      final entry = SlaLedgerMapper.mapToEntry(evidence);

      expect(entry.type, 'TRIP_INTERRUPTED');
      expect(entry.setId, 'trip-789');
      expect(entry.contractId, 'N/A');
      expect(entry.planVersion, 0);
      expect(entry.occurredAtUtc, now);

      expect(entry.payload['vehicle_id'], 'veh-001');
      expect(entry.payload['operator_id'], 'operator-cd');
      expect(entry.payload['reason'], 'Pneu Furado');
    });

    test('TripCancelledEvidence maps gracefully', () {
      final evidence = TripCancelledEvidence(
        organizationId: 'org-1',
        occurredAtUtc: now,
        tripId: 'trip-789',
        vehicleId: null,
        operatorId: 'operator-ef',
        reason: 'Problemas Mecânicos',
      );

      final entry = SlaLedgerMapper.mapToEntry(evidence);

      expect(entry.type, 'TRIP_CANCELLED');
      expect(entry.setId, 'trip-789');
      expect(entry.contractId, 'N/A');
      expect(entry.planVersion, 0);
      expect(entry.occurredAtUtc, now);

      expect(entry.payload['vehicle_id'], isNull);
      expect(entry.payload['operator_id'], 'operator-ef');
      expect(entry.payload['reason'], 'Problemas Mecânicos');
    });
  });
}
