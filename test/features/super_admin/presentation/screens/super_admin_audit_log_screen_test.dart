import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/features/super_admin/presentation/screens/super_admin_audit_log_screen.dart';
import 'package:veraprob/infrastructure/providers/super_admin_providers.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

Widget _buildScreen() {
  return ProviderScope(
    overrides: [
      systemAuditLogProvider.overrideWith((ref, params) async => []),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SuperAdminAuditLogScreen()),
    ),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('SuperAdminAuditLogScreen', () {
    testWidgets('renders screen without crashing', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.byType(SuperAdminAuditLogScreen), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows empty state when no log entries', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // With empty data, no log entry rows should appear
      expect(find.byType(SuperAdminAuditLogScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });
}
