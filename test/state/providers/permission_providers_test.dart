import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/testing/fakes/fake_jwt.dart';

AuthState _authStateFor(
  Map<String, dynamic> appMetadata, {
  String userId = 'user-1',
}) {
  return AuthState(
    AuthChangeEvent.signedIn,
    fakeSessionWithAppMeta(appMetadata, userId: userId),
  );
}

void main() {
  group('currentPermissionsProvider', () {
    test('parses app_metadata.permissions into a typed Set<String>', () async {
      final controller = StreamController<AuthState>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith((ref) => controller.stream)],
      );
      addTearDown(container.dispose);
      container.listen(currentPermissionsProvider, (_, _) {});

      controller.add(
        _authStateFor({
          'permissions': ['financial:read', 'sla:read'],
        }),
      );
      await pumpEventQueue();

      expect(container.read(currentPermissionsProvider), {
        'financial:read',
        'sla:read',
      });
    });

    test(
      'user switch tears down old permissions (no stale RAM cache)',
      () async {
        final controller = StreamController<AuthState>();
        addTearDown(controller.close);
        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => controller.stream),
          ],
        );
        addTearDown(container.dispose);
        container.listen(currentPermissionsProvider, (_, _) {});

        controller.add(
          _authStateFor({
            'permissions': ['financial:read', 'sla:approve'],
          }),
        );
        await pumpEventQueue();
        expect(container.read(currentPermissionsProvider), {
          'financial:read',
          'sla:approve',
        });

        // Different user signs in — must reflect ONLY the new set.
        controller.add(
          _authStateFor({
            'permissions': ['telemetry:read'],
          }),
        );
        await pumpEventQueue();
        expect(container.read(currentPermissionsProvider), {'telemetry:read'});
      },
    );

    test(
      'signOut zeroes permissions, scopes and perms_v; a new signIn reflects '
      'only the new user',
      () async {
        final controller = StreamController<AuthState>();
        addTearDown(controller.close);
        final container = ProviderContainer(
          overrides: [
            authStateProvider.overrideWith((ref) => controller.stream),
          ],
        );
        addTearDown(container.dispose);
        container.listen(currentPermissionsProvider, (_, _) {});
        container.listen(permScopesProvider, (_, _) {});
        container.listen(tokenPermsVersionProvider, (_, _) {});

        // 1. User A signed in — all three claim providers populate.
        controller.add(
          _authStateFor({
            'permissions': ['financial:read'],
            'perm_scopes': {
              'financial:read': ['c1'],
            },
            'perms_v': 100,
          }),
        );
        await pumpEventQueue();
        expect(container.read(currentPermissionsProvider), {'financial:read'});
        expect(container.read(permScopesProvider), {
          'financial:read': {'c1'},
        });
        expect(container.read(tokenPermsVersionProvider), 100);

        // 2. Sign out — every claim resets (no stale RAM cache survives).
        controller.add(const AuthState(AuthChangeEvent.signedOut, null));
        await pumpEventQueue();
        expect(container.read(currentPermissionsProvider), isEmpty);
        expect(container.read(permScopesProvider), isEmpty);
        expect(container.read(tokenPermsVersionProvider), 0);

        // 3. Different user signs in — only user B's claims are visible.
        controller.add(
          _authStateFor({
            'permissions': ['telemetry:read'],
          }, userId: 'user-2'),
        );
        await pumpEventQueue();
        expect(container.read(currentPermissionsProvider), {'telemetry:read'});
        expect(container.read(permScopesProvider), isEmpty);
      },
    );

    test('malformed / missing permissions → empty set', () async {
      final controller = StreamController<AuthState>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith((ref) => controller.stream)],
      );
      addTearDown(container.dispose);
      container.listen(currentPermissionsProvider, (_, _) {});

      controller.add(_authStateFor(const {}));
      await pumpEventQueue();

      expect(container.read(currentPermissionsProvider), isEmpty);
    });
  });

  group('permScopesProvider', () {
    test('parses perm_scopes into Map<String, Set<String>>', () async {
      final controller = StreamController<AuthState>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith((ref) => controller.stream)],
      );
      addTearDown(container.dispose);
      container.listen(permScopesProvider, (_, _) {});

      controller.add(
        _authStateFor({
          'permissions': ['financial:read'],
          'perm_scopes': {
            'financial:read': ['c1', 'c2'],
          },
        }),
      );
      await pumpEventQueue();

      expect(container.read(permScopesProvider), {
        'financial:read': {'c1', 'c2'},
      });
    });
  });

  group('tokenPermsVersionProvider', () {
    test('reads perms_v epoch as int', () async {
      final controller = StreamController<AuthState>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith((ref) => controller.stream)],
      );
      addTearDown(container.dispose);
      container.listen(tokenPermsVersionProvider, (_, _) {});

      controller.add(
        _authStateFor({
          'permissions': ['financial:read'],
          'perms_v': 1767225600,
        }),
      );
      await pumpEventQueue();

      expect(container.read(tokenPermsVersionProvider), 1767225600);
    });

    test('coerces a double perms_v to int and junk to 0', () async {
      final controller = StreamController<AuthState>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [authStateProvider.overrideWith((ref) => controller.stream)],
      );
      addTearDown(container.dispose);
      container.listen(tokenPermsVersionProvider, (_, _) {});

      controller.add(_authStateFor({'perms_v': 1767225600.0}));
      await pumpEventQueue();
      expect(container.read(tokenPermsVersionProvider), 1767225600);

      controller.add(_authStateFor({'perms_v': 'not-a-number'}));
      await pumpEventQueue();
      expect(container.read(tokenPermsVersionProvider), 0);
    });
  });
}
