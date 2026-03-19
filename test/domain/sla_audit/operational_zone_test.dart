import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

void main() {
  // ── Shared helper ──────────────────────────────────────────

  const kGeofence = GeofenceConfiguration(
    latitude: -23.5505,
    longitude: -46.6333,
    radiusMeters: 200,
  );

  // ── OperationalZone.create ─────────────────────────────────

  group('OperationalZone.create', () {
    test('gera UUID v4', () {
      final z1 = OperationalZone.create(
          organizationId: 'org-1', name: 'Zona A', type: ZoneType.garagem);
      final z2 = OperationalZone.create(
          organizationId: 'org-1', name: 'Zona B', type: ZoneType.garagem);

      expect(z1.id, isNotEmpty);
      expect(z2.id, isNotEmpty);
      expect(z1.id, isNot(equals(z2.id)));
    });

    test('preserva campos incluindo contractorLabel', () {
      final z = OperationalZone.create(
        organizationId: 'org-1',
        name: 'Portaria Sul',
        type: ZoneType.cliente,
        address: 'Av. Paulista, 1000',
        contractorLabel: 'Empresa ABC',
        geofence: kGeofence,
      );

      expect(z.organizationId, 'org-1');
      expect(z.name, 'Portaria Sul');
      expect(z.type, ZoneType.cliente);
      expect(z.address, 'Av. Paulista, 1000');
      expect(z.contractorLabel, 'Empresa ABC');
      expect(z.geofence, kGeofence);
    });

    test('trim e null de contractorLabel vazio', () {
      final zEmpty = OperationalZone.create(
        organizationId: 'org-1',
        name: 'Zona',
        type: ZoneType.apoio,
        contractorLabel: '   ',
      );
      expect(zEmpty.contractorLabel, isNull);

      final zNull = OperationalZone.create(
        organizationId: 'org-1',
        name: 'Zona',
        type: ZoneType.apoio,
        contractorLabel: null,
      );
      expect(zNull.contractorLabel, isNull);
    });

    test('lança DomainException se name vazio', () {
      expect(
        () => OperationalZone.create(
            organizationId: 'org-1', name: '', type: ZoneType.garagem),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se name > 100 chars', () {
      expect(
        () => OperationalZone.create(
            organizationId: 'org-1', name: 'x' * 101, type: ZoneType.garagem),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se lat fora de [-90, 90]', () {
      expect(
        () => OperationalZone.create(
          organizationId: 'org-1',
          name: 'Zona',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
              latitude: 91, longitude: 0, radiusMeters: 200),
        ),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => OperationalZone.create(
          organizationId: 'org-1',
          name: 'Zona',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
              latitude: -91, longitude: 0, radiusMeters: 200),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se lng fora de [-180, 180]', () {
      expect(
        () => OperationalZone.create(
          organizationId: 'org-1',
          name: 'Zona',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
              latitude: 0, longitude: 181, radiusMeters: 200),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se radius <= 0 ou > 50000', () {
      expect(
        () => OperationalZone.create(
          organizationId: 'org-1',
          name: 'Zona',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
              latitude: 0, longitude: 0, radiusMeters: 0),
        ),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => OperationalZone.create(
          organizationId: 'org-1',
          name: 'Zona',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
              latitude: 0, longitude: 0, radiusMeters: 50001),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('aceita geofence null (sem bloco)', () {
      final z = OperationalZone.create(
        organizationId: 'org-1',
        name: 'Zona Simples',
        type: ZoneType.apoio,
      );

      expect(z.geofence, isNull);
    });
  });

  // ── ZoneScope getter ──────────────────────────────────────

  group('ZoneScope getter', () {
    test('zona sem contractorLabel tem scope global', () {
      final z = OperationalZone.create(
        organizationId: 'org-1',
        name: 'Garagem Central',
        type: ZoneType.garagem,
      );
      expect(z.scope, ZoneScope.global);
    });

    test('zona com contractorLabel tem scope exclusive', () {
      final z = OperationalZone.create(
        organizationId: 'org-1',
        name: 'Portaria ACME',
        type: ZoneType.cliente,
        contractorLabel: 'ACME Corp',
      );
      expect(z.scope, ZoneScope.exclusive);
    });

    test('contractorLabel vazio (normalizado para null) → scope global', () {
      final z = OperationalZone.create(
        organizationId: 'org-1',
        name: 'Zona',
        type: ZoneType.apoio,
        contractorLabel: '   ',
      );
      expect(z.contractorLabel, isNull);
      expect(z.scope, ZoneScope.global);
    });
  });

  // ── OperationalZone.reconstitute ──────────────────────────

  group('OperationalZone.reconstitute', () {
    test('não revalida', () {
      final z = OperationalZone.reconstitute(
        id: 'uuid-abc',
        organizationId: 'org-1',
        name: '',
        type: ZoneType.garagem,
      );

      expect(z.id, 'uuid-abc');
      expect(z.name, '');
    });
  });
}
