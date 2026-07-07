import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/features/shared/widgets/permission_gate.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/testing/fakes/fake_jwt.dart';

AuthState _authStateFor(Map<String, dynamic> appMetadata) {
  return AuthState(
    AuthChangeEvent.signedIn,
    fakeSessionWithAppMeta(appMetadata),
  );
}

void main() {
  testWidgets('PermissionGate shows/hides as the session permissions change', (
    tester,
  ) async {
    final controller = StreamController<AuthState>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => controller.stream)],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: PermissionGate(
            permission: 'financial:read',
            fallback: Text('denied'),
            child: Text('granted'),
          ),
        ),
      ),
    );

    // No session yet → fallback.
    await tester.pump();
    expect(find.text('denied'), findsOneWidget);
    expect(find.text('granted'), findsNothing);

    // User with financial:read → child.
    controller.add(
      _authStateFor({
        'permissions': ['financial:read'],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('granted'), findsOneWidget);
    expect(find.text('denied'), findsNothing);

    // Switch to a coarse user without it → fallback again (no stale cache).
    controller.add(
      _authStateFor({
        'permissions': ['telemetry:read'],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('denied'), findsOneWidget);
    expect(find.text('granted'), findsNothing);
  });
}
