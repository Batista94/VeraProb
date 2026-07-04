import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/app/routing/route_permissions.dart';

void main() {
  group('requiredPermissionFor', () {
    test('gated pillar + hub routes map to financial:read', () {
      expect(
        requiredPermissionFor('/admin/financial-impact'),
        'financial:read',
      );
      expect(
        requiredPermissionFor('/admin/hub/billing-reports'),
        'financial:read',
      );
    });

    test('nested deep link inherits the parent gate', () {
      expect(
        requiredPermissionFor('/admin/hub/billing-reports/42'),
        'financial:read',
      );
    });

    test('ungated route returns null', () {
      expect(requiredPermissionFor('/admin/dashboard'), isNull);
    });
  });

  group('rbacRouteRedirect', () {
    test('ungated route proceeds, never fires onDenied', () {
      var fired = false;
      final redirect = rbacRouteRedirect(
        '/admin/dashboard',
        const ['telemetry:read'],
        onDenied: (_, _) => fired = true,
      );
      expect(redirect, isNull);
      expect(fired, isFalse);
    });

    test('coarse operator is ejected + ACCESS_DENIED fired with route/perm', () {
      String? route;
      String? perm;
      final redirect = rbacRouteRedirect(
        '/admin/financial-impact',
        const ['telemetry:read'],
        onDenied: (r, p) {
          route = r;
          perm = p;
        },
      );
      expect(redirect, AppRoutes.adminHub);
      expect(route, '/admin/financial-impact');
      expect(perm, 'financial:read');
    });

    test('holding the exact permission proceeds silently', () {
      var fired = false;
      final redirect = rbacRouteRedirect(
        '/admin/financial-impact',
        const ['financial:read'],
        onDenied: (_, _) => fired = true,
      );
      expect(redirect, isNull);
      expect(fired, isFalse);
    });

    test('wildcard (TENANT_ADMIN) proceeds silently', () {
      var fired = false;
      final redirect = rbacRouteRedirect(
        '/admin/hub/billing-reports',
        const ['*'],
        onDenied: (_, _) => fired = true,
      );
      expect(redirect, isNull);
      expect(fired, isFalse);
    });
  });
}
