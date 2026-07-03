import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/state/providers/permissions_sync.dart';

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
}
