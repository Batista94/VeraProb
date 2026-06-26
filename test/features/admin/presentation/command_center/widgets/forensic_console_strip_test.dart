import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/forensic_console_strip.dart';
import 'package:veraprob/state/providers/forensic_ledger_providers.dart';

void main() {
  group('ForensicConsoleStrip error UI (UX-RAW-EXCEPTION guard)', () {
    testWidgets('stream error shows sanitised domain message', (tester) async {
      tester.view.physicalSize = const Size(1200, 60);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forensicLedgerProjectionProvider.overrideWith(
              (_) => Stream.error('ledger-fail'),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ForensicConsoleStrip()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Erro ao exibir registros forenses.'), findsOneWidget);
      expect(find.textContaining('ledger-fail'), findsNothing);
      expect(find.textContaining('LEDGER ERROR'), findsNothing);
    });
  });
}
