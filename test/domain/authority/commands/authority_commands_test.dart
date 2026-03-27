import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/authority/commands/trips/acknowledge_alert_command.dart';
import 'package:veraprob/domain/authority/commands/trips/create_trip_event_command.dart';
import 'package:veraprob/domain/authority/commands/trips/override_route_deviation_command.dart';
import 'package:veraprob/domain/authority/commands/trips/update_trip_status_command.dart';
import 'package:veraprob/domain/authority/commands/vehicles/reassign_vehicle_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

void main() {
  group('AcknowledgeAlertCommand', () {
    test('targetRef points to the trip entity', () {
      const cmd = AcknowledgeAlertCommand(tripId: 'trip-abc');
      expect(cmd.targetRef.entityType, 'trip');
      expect(cmd.targetRef.entityId, 'trip-abc');
    });

    test('equality is value-based', () {
      const a = AcknowledgeAlertCommand(tripId: 'trip-1');
      const b = AcknowledgeAlertCommand(tripId: 'trip-1');
      expect(a, equals(b));
    });
  });

  group('CreateTripEventCommand', () {
    test('targetRef points to the trip entity', () {
      const cmd = CreateTripEventCommand(
        tripId: 'trip-xyz',
        type: EventType.delayDetected,
      );
      expect(cmd.targetRef, TargetRef('trip', 'trip-xyz'));
    });

    test('supports optional metadata and notes', () {
      const cmd = CreateTripEventCommand(
        tripId: 'trip-1',
        type: EventType.manualOverride,
        metadata: {'reason': 'mechanical failure'},
        notes: 'Driver reported engine issue.',
      );
      expect(cmd.metadata, {'reason': 'mechanical failure'});
      expect(cmd.notes, 'Driver reported engine issue.');
    });
  });

  group('OverrideRouteDeviationCommand', () {
    test('targetRef points to the trip entity', () {
      const cmd = OverrideRouteDeviationCommand(
        tripId: 'trip-dev-1',
        isAuthorized: true,
      );
      expect(cmd.targetRef.entityType, 'trip');
      expect(cmd.targetRef.entityId, 'trip-dev-1');
    });
  });

  group('UpdateTripStatusCommand', () {
    test('targetRef points to the trip entity', () {
      const cmd = UpdateTripStatusCommand(
        tripId: 'trip-status-1',
        newStatus: TripStatus.enRoute,
      );
      expect(cmd.targetRef.entityType, 'trip');
      expect(cmd.targetRef.entityId, 'trip-status-1');
    });

    test('stores newStatus', () {
      const cmd = UpdateTripStatusCommand(
        tripId: 'trip-2',
        newStatus: TripStatus.completed,
      );
      expect(cmd.newStatus, TripStatus.completed);
    });
  });

  group('ReassignVehicleCommand', () {
    test('targetRef points to the trip entity', () {
      const cmd = ReassignVehicleCommand(
        tripId: 'trip-r1',
        oldVehicleId: 'veh-old',
        newVehicleId: 'veh-new',
      );
      expect(cmd.targetRef.entityType, 'trip');
      expect(cmd.targetRef.entityId, 'trip-r1');
    });

    test('stores vehicle reassignment payload', () {
      const cmd = ReassignVehicleCommand(
        tripId: 'trip-r1',
        oldVehicleId: 'veh-old',
        newVehicleId: 'veh-new',
        reason: 'Breakdown',
      );
      expect(cmd.oldVehicleId, 'veh-old');
      expect(cmd.newVehicleId, 'veh-new');
      expect(cmd.reason, 'Breakdown');
    });
  });

  group('TargetRef', () {
    test('urn getter formats correctly', () {
      const ref = TargetRef('vehicle', 'veh-123');
      expect(ref.urn, 'urn:veraprob:vehicle:veh-123');
    });

    test('equality is value-based', () {
      expect(const TargetRef('trip', 'abc'), equals(const TargetRef('trip', 'abc')));
      expect(const TargetRef('trip', 'abc'), isNot(equals(const TargetRef('trip', 'xyz'))));
    });
  });
}
