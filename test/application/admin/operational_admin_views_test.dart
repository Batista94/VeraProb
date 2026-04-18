import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/invitation_view.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';

void main() {
  group('OperationalZoneView.fromDomain/toDomain', () {
    test('DEVE preservar todos os campos QUANDO round-trip sem geofence', () {
      final domain = OperationalZone.reconstitute(
        id: 'zone-1',
        organizationId: 'org-1',
        name: 'Garagem Central',
        type: ZoneType.garagem,
        address: 'Av. Paulista, 1000',
      );

      final view = OperationalZoneView.fromDomain(domain);
      final restored = view.toDomain();

      expect(view.id, 'zone-1');
      expect(view.organizationId, 'org-1');
      expect(view.name, 'Garagem Central');
      expect(view.type, ZoneType.garagem);
      expect(view.address, 'Av. Paulista, 1000');
      expect(view.contractorId, isNull);
      expect(view.contractorLabel, isNull);
      expect(view.geofence, isNull);

      expect(restored, equals(domain));
      expect(restored.address, domain.address);
    });

    test('DEVE preservar geofence + contractor QUANDO round-trip completo', () {
      final domain = OperationalZone.reconstitute(
        id: 'zone-2',
        organizationId: 'org-1',
        name: 'Cliente Norte',
        type: ZoneType.cliente,
        contractorId: 'contractor-42',
        contractorLabel: 'ACME Corp',
        geofence: const GeofenceConfiguration(
          latitude: -23.5505,
          longitude: -46.6333,
          radiusMeters: 250,
        ),
      );

      final view = OperationalZoneView.fromDomain(domain);
      final restored = view.toDomain();

      expect(view.contractorId, 'contractor-42');
      expect(view.contractorLabel, 'ACME Corp');
      expect(view.geofence, isNotNull);
      expect(view.geofence!.latitude, -23.5505);
      expect(view.geofence!.longitude, -46.6333);
      expect(view.geofence!.radiusMeters, 250);

      expect(restored, equals(domain));
      expect(restored.geofence, equals(domain.geofence));
      expect(restored.contractorId, 'contractor-42');
      expect(restored.contractorLabel, 'ACME Corp');
    });
  });

  group('OperationalZoneView.scope', () {
    test(
      'DEVE retornar global QUANDO contractorId e contractorLabel ausentes',
      () {
        const view = OperationalZoneView(
          id: 'zone-g',
          organizationId: 'org-1',
          name: 'Apoio',
          type: ZoneType.apoio,
        );
        expect(view.scope, ZoneScope.global);
      },
    );

    test('DEVE retornar exclusive QUANDO contractorId presente', () {
      const view = OperationalZoneView(
        id: 'zone-e1',
        organizationId: 'org-1',
        name: 'Portaria Sul',
        type: ZoneType.cliente,
        contractorId: 'contractor-1',
      );
      expect(view.scope, ZoneScope.exclusive);
    });

    test('DEVE retornar exclusive QUANDO apenas contractorLabel presente', () {
      const view = OperationalZoneView(
        id: 'zone-e2',
        organizationId: 'org-1',
        name: 'Portaria Leste',
        type: ZoneType.cliente,
        contractorLabel: 'ACME Corp',
      );
      expect(view.scope, ZoneScope.exclusive);
    });

    test('DEVE retornar exclusive QUANDO contractorId e label presentes', () {
      const view = OperationalZoneView(
        id: 'zone-e3',
        organizationId: 'org-1',
        name: 'Portaria Oeste',
        type: ZoneType.cliente,
        contractorId: 'contractor-9',
        contractorLabel: 'ACME Corp',
      );
      expect(view.scope, ZoneScope.exclusive);
    });
  });

  group('GeofenceView.fromDomain/toDomain', () {
    test('DEVE preservar lat/lng/radius QUANDO round-trip', () {
      const domain = GeofenceConfiguration(
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 500,
      );

      final view = GeofenceView.fromDomain(domain);

      expect(view.latitude, 40.7128);
      expect(view.longitude, -74.0060);
      expect(view.radiusMeters, 500);
      expect(view.latitude, isA<double>());
      expect(view.longitude, isA<double>());
      expect(view.radiusMeters, isA<int>());

      final restored = view.toDomain();
      expect(restored, equals(domain));
    });

    test('DEVE preservar valores negativos e zero QUANDO coord equatorial', () {
      const domain = GeofenceConfiguration(
        latitude: -0.0,
        longitude: -89.9999,
        radiusMeters: 1,
      );

      final view = GeofenceView.fromDomain(domain);
      final restored = view.toDomain();

      expect(restored.latitude, domain.latitude);
      expect(restored.longitude, domain.longitude);
      expect(restored.radiusMeters, 1);
    });
  });

  group('InvitationView.fromDomain — state propagation via nowUtc', () {
    final createdAt = DateTime.utc(2026, 4, 1);
    final expiresAt = DateTime.utc(2026, 4, 8);

    Invitation makeInvite({
      DateTime? acceptedAtUtc,
      DateTime? revokedAtUtc,
      DateTime? expires,
    }) {
      return Invitation(
        id: 'inv-1',
        organizationId: 'org-1',
        email: 'user@example.com',
        role: UserRole.operator,
        token: 'tok-abc',
        invitedBy: 'admin-1',
        createdAtUtc: createdAt,
        expiresAtUtc: expires ?? expiresAt,
        acceptedAtUtc: acceptedAtUtc,
        revokedAtUtc: revokedAtUtc,
      );
    }

    test(
      'DEVE marcar isActive=true QUANDO nowUtc antes de expiresAt e sem aceite/revogação',
      () {
        final invite = makeInvite();
        final nowUtc = DateTime.utc(2026, 4, 5);

        final view = InvitationView.fromDomain(invite, nowUtc);

        expect(view.isActive, isTrue);
        expect(view.isExpired, isFalse);
        expect(view.isAccepted, isFalse);
        expect(view.id, 'inv-1');
        expect(view.organizationId, 'org-1');
        expect(view.email, 'user@example.com');
        expect(view.role, UserRole.operator);
        expect(view.token, 'tok-abc');
        expect(view.invitedBy, 'admin-1');
        expect(view.createdAtUtc, createdAt);
        expect(view.expiresAtUtc, expiresAt);
      },
    );

    test(
      'DEVE marcar isExpired=true e isActive=false QUANDO nowUtc após expiresAt',
      () {
        final invite = makeInvite();
        final nowUtc = DateTime.utc(2026, 4, 10);

        final view = InvitationView.fromDomain(invite, nowUtc);

        expect(view.isExpired, isTrue);
        expect(view.isActive, isFalse);
        expect(view.isAccepted, isFalse);
      },
    );

    test(
      'DEVE marcar isAccepted=true e isActive=false QUANDO acceptedAtUtc definido',
      () {
        final invite = makeInvite(acceptedAtUtc: DateTime.utc(2026, 4, 3));
        final nowUtc = DateTime.utc(2026, 4, 5);

        final view = InvitationView.fromDomain(invite, nowUtc);

        expect(view.isAccepted, isTrue);
        expect(view.isActive, isFalse);
        expect(view.isExpired, isFalse);
      },
    );

    test(
      'DEVE marcar isActive=false QUANDO revogado ainda dentro do prazo',
      () {
        final invite = makeInvite(revokedAtUtc: DateTime.utc(2026, 4, 4));
        final nowUtc = DateTime.utc(2026, 4, 5);

        final view = InvitationView.fromDomain(invite, nowUtc);

        expect(view.isActive, isFalse);
        expect(view.isExpired, isFalse);
        expect(view.isAccepted, isFalse);
      },
    );

    test('DEVE tratar isAfter(expiresAt) como expirado (limite estrito)', () {
      final invite = makeInvite(expires: DateTime.utc(2026, 4, 8));
      final atBoundary = DateTime.utc(2026, 4, 8);
      final afterBoundary = DateTime.utc(2026, 4, 8, 0, 0, 1);

      final viewAt = InvitationView.fromDomain(invite, atBoundary);
      final viewAfter = InvitationView.fromDomain(invite, afterBoundary);

      expect(viewAt.isExpired, isFalse);
      expect(viewAt.isActive, isTrue);
      expect(viewAfter.isExpired, isTrue);
      expect(viewAfter.isActive, isFalse);
    });
  });
}
