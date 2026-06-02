import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue_screen.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

class _MockSealedNotifier extends SealedSanctionsNotifier {
  final SealedSanctionsState mockState;
  _MockSealedNotifier(this.mockState);

  @override
  SealedSanctionsState build() => mockState;

  @override
  Future<void> fetchNextPage({bool clear = false}) async {}
}

final mockSealedState = SealedSanctionsState(
  items: const [],
  isLoading: false,
  hasMore: false,
  startDate: DateTime.utc(2026, 1, 1),
  endDate: DateTime.utc(2026, 1, 8),
);

Widget _buildScreen({List<Override> extraOverrides = const []}) {
  return ProviderScope(
    overrides: [
      pendingSanctionsStreamProvider.overrideWith((ref) => Stream.value([])),
      sealedSanctionsNotifierProvider.overrideWith(
        () => _MockSealedNotifier(mockSealedState),
      ),
      ...extraOverrides,
    ],
    child: const MaterialApp(home: AuditorQueueScreen()),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('AuditorQueueScreen', () {
    testWidgets('renders header title and SegmentedButton tabs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Tribunal de Auditoria'), findsOneWidget);
      expect(find.textContaining('Pendentes'), findsOneWidget);
      expect(find.text('Selados'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows empty state when no pending sanctions', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Nenhum veredito pendente'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets(
      'toggling to Selados shows DateFilterBar and sealed empty state',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(_buildScreen());
        await tester.pumpAndSettle();

        // Tap on the "Selados" tab segment
        await tester.tap(find.text('Selados'));
        await tester.pumpAndSettle();

        // Date range filter bar must render
        expect(find.textContaining('Período:'), findsOneWidget);
        expect(
          find.text('Nenhum veredito selado encontrado neste período.'),
          findsOneWidget,
        );

        addTearDown(tester.view.resetPhysicalSize);
      },
    );
  });
}
