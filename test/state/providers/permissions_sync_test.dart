import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/permissions_sync.dart';
import 'package:veraprob/testing/fakes/fake_jwt.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    // Constructed but never connected — reconcile() uses injected readDbVersion,
    // and start()/Realtime is not exercised in these unit tests.
    client = SupabaseClient('http://localhost:54321', 'test-anon-key');
  });

  tearDown(() async {
    await client.dispose();
  });

  PermissionsSyncController build({
    required Future<int> Function() readDbVersion,
    required int Function() readTokenVersion,
    required Future<void> Function() onRefresh,
  }) {
    final controller = PermissionsSyncController(
      client: client,
      readDbVersion: readDbVersion,
      onRefresh: onRefresh,
      readTokenVersion: readTokenVersion,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('divergent version triggers exactly one refresh', () async {
    var refreshes = 0;
    final controller = build(
      readDbVersion: () async => 99,
      readTokenVersion: () => 1,
      onRefresh: () async => refreshes++,
    );

    await controller.reconcile();

    expect(refreshes, 1);
  });

  test('matching version is a no-op (no refresh, no loop)', () async {
    var refreshes = 0;
    final controller = build(
      readDbVersion: () async => 5,
      readTokenVersion: () => 5,
      onRefresh: () async => refreshes++,
    );

    await controller.reconcile();
    await controller.reconcile();

    expect(refreshes, 0);
  });

  test('overlapping reconciles are debounced to a single refresh', () async {
    var refreshes = 0;
    final gate = Completer<void>();
    final controller = build(
      readDbVersion: () async {
        await gate.future; // hold the first run in-flight
        return 42;
      },
      readTokenVersion: () => 1,
      onRefresh: () async => refreshes++,
    );

    final first = controller.reconcile();
    final second = controller.reconcile(); // rejected by _isSyncing guard

    gate.complete();
    await Future.wait([first, second]);

    expect(refreshes, 1);
  });

  test('readDbVersion failure is swallowed and the guard resets', () async {
    var refreshes = 0;
    var calls = 0;
    final controller = build(
      // 1st reconcile throws; the guard must reset so a later reconcile runs.
      readDbVersion: () async {
        calls++;
        if (calls == 1) throw const PostgrestException(message: 'boom');
        return 99;
      },
      readTokenVersion: () => 1,
      onRefresh: () async => refreshes++,
    );

    await controller.reconcile(); // failure swallowed, no refresh
    expect(refreshes, 0);

    await controller.reconcile(); // guard reset → diverges → refreshes once
    expect(refreshes, 1);
  });

  test(
    'dispose() during an in-flight reconcile suppresses the refresh',
    () async {
      var refreshes = 0;
      final gate = Completer<void>();
      final controller = build(
        readDbVersion: () async {
          await gate.future; // hold the run in-flight
          return 42; // would diverge from token version 1
        },
        readTokenVersion: () => 1,
        onRefresh: () async => refreshes++,
      );

      final inFlight = controller.reconcile();
      controller.dispose(); // logout mid-reconcile
      gate.complete();
      await inFlight;

      expect(refreshes, 0);
    },
  );

  group('permissionsSyncProvider', () {
    test('wildcard holder skips sync (returns null)', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              AuthState(
                AuthChangeEvent.signedIn,
                fakeSessionWithAppMeta({
                  'permissions': ['*'],
                }),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateProvider, (_, _) {});
      await pumpEventQueue();

      expect(container.read(permissionsSyncProvider), isNull);
    });

    test('signed-out session yields no controller (returns null)', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authStateProvider, (_, _) {});
      await pumpEventQueue();

      expect(container.read(permissionsSyncProvider), isNull);
    });
  });
}
