import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/transit_route.dart';

void main() {
  group('TransitRoute', () {
    TransitRoute buildRoute({
      String id = 'r-001',
      String organizationId = 'org-1',
      String? gtfsRouteId = '809U-10',
      String shortName = '809U',
      String longName = 'Cidade Universitária',
      String? color = '#FF5722',
      String? agencyId = 'SPTRANS',
      DateTime? createdAt,
      int? activeTripsCount,
    }) => TransitRoute(
      id: id,
      organizationId: organizationId,
      gtfsRouteId: gtfsRouteId,
      shortName: shortName,
      longName: longName,
      color: color,
      agencyId: agencyId,
      createdAt: createdAt,
      activeTripsCount: activeTripsCount,
    );

    test('displayName combines shortName and longName', () {
      final route = buildRoute(
        shortName: '809U',
        longName: 'Cidade Universitária',
      );
      expect(route.displayName, '809U — Cidade Universitária');
    });

    test('copyWith overrides specified fields', () {
      final route = buildRoute();
      final copy = route.copyWith(
        shortName: 'NEW',
        longName: 'New Long Name',
        activeTripsCount: 5,
      );
      expect(copy.shortName, 'NEW');
      expect(copy.longName, 'New Long Name');
      expect(copy.activeTripsCount, 5);
      expect(copy.id, route.id);
      expect(copy.organizationId, route.organizationId);
    });

    test('copyWith preserves nullable fields', () {
      final route = buildRoute(gtfsRouteId: null, color: null, agencyId: null);
      final copy = route.copyWith();
      expect(copy.gtfsRouteId, isNull);
      expect(copy.color, isNull);
      expect(copy.agencyId, isNull);
    });

    test('fromJson parses all fields', () {
      final json = {
        'id': 'r-123',
        'organization_id': 'org-abc',
        'gtfs_route_id': '809U-10',
        'short_name': '809U',
        'long_name': 'Cidade Universitária',
        'color': '#FF5722',
        'agency_id': 'SPTRANS',
        'created_at': '2026-01-01T00:00:00.000Z',
      };
      final route = TransitRoute.fromJson(json);
      expect(route.id, 'r-123');
      expect(route.organizationId, 'org-abc');
      expect(route.gtfsRouteId, '809U-10');
      expect(route.shortName, '809U');
      expect(route.longName, 'Cidade Universitária');
      expect(route.color, '#FF5722');
      expect(route.agencyId, 'SPTRANS');
      expect(route.createdAt, isNotNull);
    });

    test('fromJson falls back to name field when short_name is absent', () {
      final json = {
        'id': 'r-fallback',
        'organization_id': 'org-x',
        'name': 'Fallback Name',
        'long_name': 'Long',
        'created_at': null,
      };
      final route = TransitRoute.fromJson(json);
      expect(route.shortName, 'Fallback Name');
    });

    test('fromJson returns empty strings when no name fields provided', () {
      final json = {
        'id': 'r-empty',
        'organization_id': 'org-x',
        'created_at': null,
      };
      final route = TransitRoute.fromJson(json);
      expect(route.shortName, '');
      expect(route.longName, '');
    });

    test('toJson produces correct map', () {
      final route = buildRoute(
        shortName: '809U',
        longName: 'Cidade Universitária',
        gtfsRouteId: '809U-10',
        color: '#FF5722',
        agencyId: 'SPTRANS',
      );
      final json = route.toJson();
      expect(json['organization_id'], 'org-1');
      expect(json['gtfs_route_id'], '809U-10');
      expect(json['short_name'], '809U');
      expect(json['long_name'], 'Cidade Universitária');
      expect(json['color'], '#FF5722');
      expect(json['agency_id'], 'SPTRANS');
    });

    test('equality based on props', () {
      final r1 = buildRoute();
      final r2 = buildRoute();
      expect(r1, equals(r2));
    });

    test('props differ when shortName differs', () {
      final r1 = buildRoute(shortName: 'A');
      final r2 = buildRoute(shortName: 'B');
      expect(r1, isNot(equals(r2)));
    });
  });
}
