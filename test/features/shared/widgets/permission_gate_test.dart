import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/features/shared/widgets/permission_gate.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

String _makeJwt(Map<String, dynamic> appMetadata) {
  final payload = <String, dynamic>{'sub': 'user-1', 'app_metadata': appMetadata};
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
  testWidgets('PermissionGate shows/hides as the session permissions change', (
    tester,
  ) async {
    final controller = StreamController<AuthState>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => controller.stream),
        ],
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
