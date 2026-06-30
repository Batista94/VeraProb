import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue/widgets/auditor_empty_state.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

Widget _wrap({required List<Override> overrides}) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: SimulateButton())),
);

void main() {
  group('SimulateButton', () {
    testWidgets('renders simulate button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            currentOrganizationIdProvider.overrideWithValue('org-123'),
          ],
        ),
      );
      await tester.pump();
      expect(find.byType(SimulateButton), findsOneWidget);
    });

    testWidgets('shows org-not-found snackbar when organization id is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [currentOrganizationIdProvider.overrideWithValue(null)],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();

      expect(
        find.text('Organização não encontrada. Faça login novamente.'),
        findsOneWidget,
      );
    });
  });
}
