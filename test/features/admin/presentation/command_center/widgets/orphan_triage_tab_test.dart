import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/orphan_triage_tab.dart';
import 'package:veraprob/state/providers/shadow_providers.dart';

void main() {
  group('OrphanTriageTab error UI (UX-RAW-EXCEPTION guard)', () {
    testWidgets('load error shows sanitised domain message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unlinkedShadowsProvider.overrideWith(
              (ref) => Future.error('network-fail'),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: OrphanTriageTab())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar os registros órfãos.'),
        findsOneWidget,
      );
      expect(find.textContaining('network-fail'), findsNothing);
    });
  });
}
