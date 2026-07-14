import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/sandbox/widgets/sandbox_banner.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );
  }

  group('SandboxBanner — cognitive shield', () {
    testWidgets('shows MODO SIMULAÇÃO warning and session label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SandboxBanner(
            sessionLabel: 'Teste Tolerância 15min',
            periodStartUtc: DateTime.utc(2026, 1, 1),
            periodEndUtc: DateTime.utc(2026, 6, 30),
            onExit: () {},
          ),
        ),
      );

      expect(find.textContaining('MODO SIMULAÇÃO'), findsOneWidget);
      expect(find.textContaining('⚠'), findsOneWidget);
      expect(find.textContaining('Teste Tolerância 15min'), findsOneWidget);
    });

    testWidgets('shows period range for cognitive context', (tester) async {
      await tester.pumpWidget(
        wrap(
          SandboxBanner(
            sessionLabel: 'Sessão A',
            periodStartUtc: DateTime.utc(2026, 1, 1),
            periodEndUtc: DateTime.utc(2026, 6, 30),
            onExit: () {},
          ),
        ),
      );

      expect(find.textContaining('2026'), findsWidgets);
    });

    testWidgets('has no dismiss/close IconButton — non-dismissible', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SandboxBanner(
            sessionLabel: 'Sessão B',
            periodStartUtc: DateTime.utc(2026, 2, 1),
            periodEndUtc: DateTime.utc(2026, 3, 1),
            onExit: () {},
          ),
        ),
      );

      expect(find.byTooltip('Fechar'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byType(CloseButton), findsNothing);
    });

    testWidgets('Sair Simulação is the only exit action and invokes onExit', (
      tester,
    ) async {
      var exited = false;
      await tester.pumpWidget(
        wrap(
          SandboxBanner(
            sessionLabel: 'Sessão C',
            periodStartUtc: DateTime.utc(2026, 1, 1),
            periodEndUtc: DateTime.utc(2026, 2, 1),
            onExit: () => exited = true,
          ),
        ),
      );

      final exitFinder = find.text('Sair Simulação');
      expect(exitFinder, findsOneWidget);

      await tester.tap(exitFinder);
      await tester.pump();
      expect(exited, isTrue);
    });

    testWidgets('banner background uses warning at 15% over surface token', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SandboxBanner(
            sessionLabel: 'Sessão D',
            periodStartUtc: DateTime.utc(2026, 1, 1),
            periodEndUtc: DateTime.utc(2026, 2, 1),
            onExit: () {},
          ),
        ),
      );

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SandboxBanner),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, VeraProbColors.warning.withValues(alpha: 0.15));
    });
  });
}
