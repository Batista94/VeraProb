import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/features/admin/presentation/screens/defense_portal_screen.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/justification_providers.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

Widget _buildScreen(ProviderScope scope) {
  return MaterialApp(home: Scaffold(body: scope));
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('DefensePortalScreen', () {
    testWidgets('renders screen title and header', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildScreen(
          ProviderScope(
            overrides: [
              justificationListStreamProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: const DefensePortalScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(VeraProbHeader), findsOneWidget);
      expect(find.text('Portal Defesa'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('renders SkeletonListLoader when loading', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      final controller = StreamController<List<Map<String, dynamic>>>();

      await tester.pumpWidget(
        _buildScreen(
          ProviderScope(
            overrides: [
              justificationListStreamProvider.overrideWith(
                (ref) => controller.stream,
              ),
            ],
            child: const DefensePortalScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(SkeletonListLoader), findsWidgets);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('renders empty state when data is empty', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildScreen(
          ProviderScope(
            overrides: [
              justificationListStreamProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: const DefensePortalScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Nenhuma justificativa encontrada'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('renders error state when error occurs', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        _buildScreen(
          ProviderScope(
            overrides: [
              justificationListStreamProvider.overrideWith(
                (ref) => Stream.error(Exception('Simulated error')),
              ),
            ],
            child: const DefensePortalScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Erro:'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });
}
