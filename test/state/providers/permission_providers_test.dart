import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

String _makeJwt(Map<String, dynamic> appMetadata) {
  final payload = <String, dynamic>{
    'sub': 'user-1',
    'app_metadata': appMetadata,
  };
  final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return 'header.$encoded.signature';
}

AuthState _authStateFor(Map<String, dynamic> appMetadata) {
  final session = Session(
    accessToken: _makeJwt(appMetadata),
    tokenType: 'bearer',
    user: User(
      id: 'user-1',
      appMetadata: const <String, dynamic>{},
      userMetadata: const <String, dynamic>{},
      aud: 'authenticated',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ),
  );
  return AuthState(AuthChangeEvent.signedIn, session);
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
  });
}
