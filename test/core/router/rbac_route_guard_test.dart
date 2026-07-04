// rbac_route_guard_test.dart
//
// Integration of the fine-grained route guard (Pilar 3) with a minimal router,
// exercising the REAL symbols (`rbacRouteRedirect` + `logAccessDenied`) rather
// than a copy. Proves the ACCESS_DENIED audit wiring (exact RPC params) and the
// silent eject (no ErrorWidget, no thrown exception — WASM-CONTEXT-LEAK safe,
// UX-RAW-EXCEPTION safe) including when the audit RPC itself fails.
//
// A full `appRouterProvider` would need dozens of AdminLayout provider overrides;
// this replicates only the guard contract, mirroring super_admin_guard_test.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/app/routing/app_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/app/routing/route_permissions.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakePostgrestFilterBuilder<T> extends Mock
    implements PostgrestFilterBuilder<T> {
  final Future<T> _future;
  FakePostgrestFilterBuilder(this._future);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    return _future.then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return _future.catchError(onError, test: test);
  }
}

const _financial = '/admin/financial-impact';

/// Minimal router whose redirect delegates to the production RBAC symbols.
GoRouter _guardedRouter(SupabaseClient client, Iterable<String> perms) {
  return GoRouter(
    initialLocation: _financial,
    redirect: (context, state) => rbacRouteRedirect(
      state.uri.path,
      perms,
      onDenied: (route, perm) =>
          unawaited(logAccessDenied(client, route, perm)),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.adminHub,
        builder: (_, _) => const Scaffold(body: Text('HUB')),
      ),
      GoRoute(
        path: _financial,
        builder: (_, _) => const Scaffold(body: Text('FINANCIAL')),
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  SupabaseClient client,
  Iterable<String> perms,
) async {
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: _guardedRouter(client, perms)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  // The result future is built lazily per call so an error future never sits
  // unhandled between setup and the guard's await (which is what swallows it).
  MockSupabaseClient clientReturning(Future<void> Function() rpcResult) {
    final client = MockSupabaseClient();
    when(
      () => client.rpc<void>('log_access_denied', params: any(named: 'params')),
    ).thenAnswer((_) => FakePostgrestFilterBuilder<void>(rpcResult()));
    return client;
  }

  testWidgets('denied route ejects to hub + fires exact ACCESS_DENIED audit', (
    tester,
  ) async {
    final client = clientReturning(() => Future<void>.value());

    await _pump(tester, client, const {'sla:read'});

    expect(find.text('HUB'), findsOneWidget);
    expect(find.text('FINANCIAL'), findsNothing);
    expect(find.byType(ErrorWidget), findsNothing);
    verify(
      () => client.rpc<void>(
        'log_access_denied',
        params: {'p_route': _financial, 'p_required_perm': 'financial:read'},
      ),
    ).called(1);
  });

  testWidgets('permitted route passes through without any audit', (
    tester,
  ) async {
    final client = clientReturning(() => Future<void>.value());

    await _pump(tester, client, const {'financial:read'});

    expect(find.text('FINANCIAL'), findsOneWidget);
    verifyNever(
      () => client.rpc<void>('log_access_denied', params: any(named: 'params')),
    );
  });

  testWidgets('wildcard permission bypasses the gate (no eject, no audit)', (
    tester,
  ) async {
    final client = clientReturning(() => Future<void>.value());

    await _pump(tester, client, const {'*'});

    expect(find.text('FINANCIAL'), findsOneWidget);
    verifyNever(
      () => client.rpc<void>('log_access_denied', params: any(named: 'params')),
    );
  });

  testWidgets('audit RPC failure still ejects silently (no leaked exception)', (
    tester,
  ) async {
    final client = clientReturning(
      () => Future<void>.error(
        const PostgrestException(message: 'RLS denied', code: '42501'),
      ),
    );

    await _pump(tester, client, const {'sla:read'});

    expect(find.text('HUB'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
