import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/shared/app_types.dart';

void main() {
  group('OperationalZoneView', () {
    test('can be constructed with required fields', () {
      const view = OperationalZoneView(
        id: 'zone-1',
        organizationId: 'org-1',
        name: 'Garagem Central',
        type: ZoneType.garagem,
      );
      expect(view.id, 'zone-1');
      expect(view.organizationId, 'org-1');
      expect(view.name, 'Garagem Central');
      expect(view.type, ZoneType.garagem);
      expect(view.scope, ZoneScope.global);
    });

    test('geofenceRadiusMeters is int (BPS-compliant for discrete metric)', () {
      const view = OperationalZoneView(
        id: 'zone-2',
        organizationId: 'org-1',
        name: 'Zona Cliente',
        type: ZoneType.cliente,
        contractorId: 'cont-1',
        geofence: GeofenceView(
          latitude: -23.5505,
          longitude: -46.6333,
          radiusMeters: 200,
        ),
      );
      expect(view.scope, ZoneScope.exclusive);
      expect(view.geofence?.radiusMeters, isA<int>());
      expect(view.geofence?.radiusMeters, 200);
    });

    test('geofenceLat and geofenceLng are double (Physical Metric)', () {
      const view = OperationalZoneView(
        id: 'zone-3',
        organizationId: 'org-1',
        name: 'Apoio',
        type: ZoneType.apoio,
        geofence: GeofenceView(
          latitude: -23.5505,
          longitude: -46.6333,
          radiusMeters: 100,
        ),
      );
      expect(view.geofence?.latitude, isA<double>());
      expect(view.geofence?.longitude, isA<double>());
    });

    test('optional fields default to null', () {
      const view = OperationalZoneView(
        id: 'zone-4',
        organizationId: 'org-1',
        name: 'Zona Simples',
        type: ZoneType.garagem,
      );
      expect(view.address, isNull);
      expect(view.contractorId, isNull);
      expect(view.geofence, isNull);
    });
  });
}
