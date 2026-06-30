import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'dart:async';
import 'package:veraprob/features/admin/presentation/screens/sla_audit_screen.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/sla_providers.dart';

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
      slaSummaryProvider.overrideWith(
        (ref) async =>
            SlaExecutionSummary.empty(generatedAtUtc: DateTime.utc(2026, 1, 1)),
      ),
      slaExceptionsProvider.overrideWith((ref) async => []),
    ],
    child: const MaterialApp(home: Scaffold(body: SlaAuditScreen())),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('SlaAuditScreen', () {
    testWidgets('renders screen title', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.byType(VeraProbHeader), findsOneWidget);
      expect(find.text('Relatório de Auditoria SLA'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('renders SkeletonListLoader when loading', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      final completer = Completer<SlaExecutionSummary>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            slaSummaryProvider.overrideWith((ref) => completer.future),
            slaExceptionsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: Scaffold(body: SlaAuditScreen())),
        ),
      );

      await tester.pump(); // Start building, future is not complete yet

      expect(find.byType(SkeletonListLoader), findsWidgets);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('renders without errors when data is empty', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Screen should be present and stable — no exception thrown
      expect(find.byType(SlaAuditScreen), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });
}
