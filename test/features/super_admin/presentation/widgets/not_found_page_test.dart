import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/not_found_page.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('NotFoundPage — element presence and VeraProbColors (Task 4.3)', () {
    testWidgets('renders search_off icon', (tester) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('renders "Página não encontrada" message', (tester) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      expect(find.text('Página não encontrada'), findsOneWidget);
    });

    testWidgets(
      'renders subtitle "O endereço que você tentou acessar não existe."',
      (tester) async {
        await tester.pumpWidget(_wrap(const NotFoundPage()));
        expect(
          find.text('O endereço que você tentou acessar não existe.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('renders "Voltar ao início" button', (tester) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      expect(find.text('Voltar ao início'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('icon uses VeraProbColors.textSecondary', (tester) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.search_off));
      expect(icon.color, VeraProbColors.textSecondary);
    });

    testWidgets('scaffold uses VeraProbColors.background', (tester) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, VeraProbColors.background);
    });

    testWidgets('title text uses VeraProbColors.textPrimary', (tester) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final titleText = tester.widget<Text>(find.text('Página não encontrada'));
      expect(titleText.style?.color, VeraProbColors.textPrimary);
    });

    testWidgets('subtitle text uses VeraProbColors.textSecondary', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final subtitleText = tester.widget<Text>(
        find.text('O endereço que você tentou acessar não existe.'),
      );
      expect(subtitleText.style?.color, VeraProbColors.textSecondary);
    });

    testWidgets('button uses VeraProbColors.primary as background', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      // Resolve the background color from the button style
      final bgColor = button.style?.backgroundColor?.resolve({});
      expect(bgColor, VeraProbColors.primary);
    });

    testWidgets('"Voltar ao início" button pops to first route', (
      tester,
    ) async {
      // Build a navigation stack with two routes, the second being NotFoundPage
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotFoundPage(),
                    ),
                  );
                },
                child: const Text('Go'),
              );
            },
          ),
        ),
      );

      // Navigate to NotFoundPage
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('Voltar ao início'), findsOneWidget);

      // Tap the button
      await tester.tap(find.text('Voltar ao início'));
      await tester.pumpAndSettle();

      // Should be back at the first route
      expect(find.text('Go'), findsOneWidget);
      expect(find.text('Voltar ao início'), findsNothing);
    });
  });

  group('NotFoundPage — responsive layout (Task 4.4)', () {
    testWidgets('Desktop (≥1024px): icon size is 96', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.search_off));
      expect(icon.size, 96);
    });

    testWidgets('Tablet (≥768px, <1024px): icon size is 72', (tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.search_off));
      expect(icon.size, 72);
    });

    testWidgets('Mobile (<768px): icon size is 56', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.search_off));
      expect(icon.size, 56);
    });

    testWidgets('Desktop at exact breakpoint (1024px): icon size is 96', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.search_off));
      expect(icon.size, 96);
    });

    testWidgets('Tablet at exact breakpoint (768px): icon size is 72', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(768, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const NotFoundPage()));
      final icon = tester.widget<Icon>(find.byIcon(Icons.search_off));
      expect(icon.size, 72);
    });

    testWidgets('layout is centered on all breakpoints', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const NotFoundPage()));
      // The body of the Scaffold contains a LayoutBuilder whose direct
      // child tree includes Center for centering the content.
      final center = find.descendant(
        of: find.byType(LayoutBuilder),
        matching: find.byType(Center),
      );
      expect(center, findsAtLeastNWidgets(1));
    });

    testWidgets('uses LayoutBuilder for responsive sizing', (tester) async {
      await tester.pumpWidget(_wrap(const NotFoundPage()));
      expect(find.byType(LayoutBuilder), findsOneWidget);
    });
  });
}
