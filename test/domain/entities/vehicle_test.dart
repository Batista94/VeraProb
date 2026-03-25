import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/vehicle.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';

void main() {
  group('Vehicle', () {
    final DateTime createdAt = DateTime.utc(2026, 1, 1);

    Vehicle buildVehicle({
      String id = 'v-001',
      String organizationId = 'org-1',
      String plate = 'ABC-1234',
      String? model = 'Mercedes O500',
      int capacity = 44,
      VehicleStatus status = VehicleStatus.available,
      DateTime? createdAt,
      String? currentTripId,
      String? currentRouteShortName,
    }) => Vehicle(
      id: id,
      organizationId: organizationId,
      plate: plate,
      model: model,
      capacity: capacity,
      status: status,
      createdAt: createdAt,
      currentTripId: currentTripId,
      currentRouteShortName: currentRouteShortName,
    );

    test('isAvailable is true when status is available', () {
      expect(buildVehicle(status: VehicleStatus.available).isAvailable, isTrue);
    });

    test('isAvailable is false when status is inService', () {
      expect(
        buildVehicle(status: VehicleStatus.inService).isAvailable,
        isFalse,
      );
    });

    test('isInService is true when status is inService', () {
      expect(buildVehicle(status: VehicleStatus.inService).isInService, isTrue);
    });

    test('isInService is false when status is available', () {
      expect(
        buildVehicle(status: VehicleStatus.available).isInService,
        isFalse,
      );
    });

    test('displayName includes model when model is present', () {
      expect(
        buildVehicle(plate: 'ABC-1234', model: 'Mercedes O500').displayName,
        'ABC-1234 (Mercedes O500)',
      );
    });

    test('displayName is just plate when model is null', () {
      expect(
        buildVehicle(plate: 'DEF-5678', model: null).displayName,
        'DEF-5678',
      );
    });

    test('copyWith overrides specified fields', () {
      final v = buildVehicle();
      final copy = v.copyWith(
        plate: 'XYZ-9999',
        status: VehicleStatus.maintenance,
        capacity: 50,
      );
      expect(copy.plate, 'XYZ-9999');
      expect(copy.status, VehicleStatus.maintenance);
      expect(copy.capacity, 50);
      expect(copy.id, v.id);
      expect(copy.organizationId, v.organizationId);
    });

    test('copyWith preserves optional nullable fields', () {
      final v = buildVehicle(model: null, currentTripId: null);
      final copy = v.copyWith();
      expect(copy.model, isNull);
      expect(copy.currentTripId, isNull);
    });

    test('fromJson parses required fields correctly', () {
      final json = {
        'id': 'v-123',
        'organization_id': 'org-abc',
        'plate': 'QWE-1111',
        'model': 'Volvo B270F',
        'capacity': 42,
        'status': 'in_service',
        'created_at': '2026-01-01T00:00:00.000Z',
      };
      final v = Vehicle.fromJson(json);
      expect(v.id, 'v-123');
      expect(v.organizationId, 'org-abc');
      expect(v.plate, 'QWE-1111');
      expect(v.model, 'Volvo B270F');
      expect(v.capacity, 42);
      expect(v.status, VehicleStatus.inService);
      expect(v.createdAt, isNotNull);
    });

    test('fromJson handles null model and created_at', () {
      final json = {
        'id': 'v-null',
        'organization_id': 'org-x',
        'plate': 'NUL-0000',
        'model': null,
        'capacity': 20,
        'status': 'available',
        'created_at': null,
      };
      final v = Vehicle.fromJson(json);
      expect(v.model, isNull);
      expect(v.createdAt, isNull);
    });

    test('toJson produces correct map', () {
      final v = buildVehicle(
        plate: 'ABC-1234',
        model: 'Mercedes O500',
        capacity: 44,
        status: VehicleStatus.inService,
      );
      final json = v.toJson();
      expect(json['plate'], 'ABC-1234');
      expect(json['model'], 'Mercedes O500');
      expect(json['capacity'], 44);
      expect(json['status'], 'in_service');
      expect(json['organization_id'], 'org-1');
    });

    test('equality uses props', () {
      final v1 = buildVehicle(createdAt: createdAt);
      final v2 = buildVehicle(createdAt: createdAt);
      expect(v1, equals(v2));
    });

    test('props differ when plate differs', () {
      final v1 = buildVehicle(plate: 'AAA-1111');
      final v2 = buildVehicle(plate: 'BBB-2222');
      expect(v1, isNot(equals(v2)));
    });
  });
}
