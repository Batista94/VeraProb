import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/services/permission_service.dart';

/// Client↔DB parity: each case here must match `public.has_permission` /
/// `public.has_permission_on` (20260909000003) for the same claim set.
void main() {
  PermissionService svc(
    Set<String> perms, [
    Map<String, Set<String>> scopes = const {},
  ]) => PermissionService(permissions: perms, scopes: scopes);

  group('hasPermission (mirrors public.has_permission)', () {
    test('present key → true', () {
      expect(svc({'financial:read'}).hasPermission('financial:read'), isTrue);
    });

    test('absent key → false (silent deny)', () {
      expect(svc({'financial:read'}).hasPermission('sla:approve'), isFalse);
    });

    test('wildcard grants any key', () {
      expect(svc({'*'}).hasPermission('anything:goes'), isTrue);
    });

    test('empty set → false', () {
      expect(svc(<String>{}).hasPermission('financial:read'), isFalse);
    });
  });

  group('hasPermissionOn (mirrors public.has_permission_on)', () {
    test('no scope entry → unrestricted (true)', () {
      expect(
        svc({'financial:read'}).hasPermissionOn('financial:read', 'c1'),
        isTrue,
      );
    });

    test('scope contains resource → true', () {
      expect(
        svc(
          {'financial:read'},
          {
            'financial:read': {'c1'},
          },
        ).hasPermissionOn('financial:read', 'c1'),
        isTrue,
      );
    });

    test('scope does NOT contain resource → false', () {
      expect(
        svc(
          {'financial:read'},
          {
            'financial:read': {'c1'},
          },
        ).hasPermissionOn('financial:read', 'c2'),
        isFalse,
      );
    });

    test('permission not held → false regardless of scope', () {
      expect(svc(<String>{}).hasPermissionOn('financial:read', 'c1'), isFalse);
    });

    test('wildcard with no scope → unrestricted (true)', () {
      expect(svc({'*'}).hasPermissionOn('financial:read', 'c9'), isTrue);
    });
  });

  group('hasAny / hasAll', () {
    test('hasAny true when at least one held', () {
      expect(svc({'sla:read'}).hasAny(['financial:read', 'sla:read']), isTrue);
    });

    test('hasAny false when none held', () {
      expect(svc({'telemetry:read'}).hasAny(['financial:read']), isFalse);
    });

    test('hasAll false when one missing', () {
      expect(
        svc({'financial:read'}).hasAll(['financial:read', 'sla:read']),
        isFalse,
      );
    });

    test('wildcard satisfies hasAll', () {
      expect(svc({'*'}).hasAll(['a:b', 'c:d']), isTrue);
    });
  });
}
