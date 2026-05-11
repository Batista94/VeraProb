import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/archive_confirmation_dialog.dart';

void main() {
  Widget buildApp({NavigatorObserver? observer}) {
    return MaterialApp(
      navigatorObservers: observer != null ? [observer] : [],
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildApp());
    final ctx = tester.element(find.byType(Scaffold));
    ArchiveConfirmationDialog.show(ctx);
    await tester.pumpAndSettle();
  }

  group('CIA Integrity — Validação de Motivo Obrigatório', () {
    testWidgets('rejeita motivo vazio', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Confirmar Arquivamento'));
      await tester.pumpAndSettle();

      expect(find.text('Motivo obrigatório.'), findsOneWidget);
    });

    testWidgets('rejeita motivo com menos de 10 caracteres', (tester) async {
      await openDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'curto');
      await tester.tap(find.text('Confirmar Arquivamento'));
      await tester.pumpAndSettle();

      expect(find.text('Mínimo 10 caracteres.'), findsOneWidget);
    });

    testWidgets(
      'rejeita motivo com espaços que resulta em < 10 chars após trim',
      (tester) async {
        await openDialog(tester);
        await tester.enterText(find.byType(TextFormField), '   abc    ');
        await tester.tap(find.text('Confirmar Arquivamento'));
        await tester.pumpAndSettle();

        expect(find.text('Mínimo 10 caracteres.'), findsOneWidget);
      },
    );

    testWidgets('aceita motivo com exatamente 10 caracteres', (tester) async {
      await openDialog(tester);
      await tester.enterText(find.byType(TextFormField), '1234567890');
      await tester.tap(find.text('Confirmar Arquivamento'));
      await tester.pumpAndSettle();

      // Dialog closes — no longer visible
      expect(find.byType(ArchiveConfirmationDialog), findsNothing);
    });

    testWidgets('retorna motivo trimado ao confirmar', (tester) async {
      await tester.pumpWidget(buildApp());
      final ctx = tester.element(find.byType(Scaffold));
      final future = ArchiveConfirmationDialog.show(ctx);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        '  Motivo válido para auditoria  ',
      );
      await tester.tap(find.text('Confirmar Arquivamento'));
      await tester.pumpAndSettle();

      final result = await future;
      expect(result, 'Motivo válido para auditoria');
    });
  });

  group('CIA Availability — Modal Persistente', () {
    testWidgets('não fecha ao tap na barreira externa', (tester) async {
      await openDialog(tester);

      // Tap outside the dialog (on the barrier)
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.byType(ArchiveConfirmationDialog), findsOneWidget);
    });

    testWidgets('fecha apenas via botão Cancelar', (tester) async {
      await tester.pumpWidget(buildApp());
      final ctx = tester.element(find.byType(Scaffold));
      final future = ArchiveConfirmationDialog.show(ctx);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      final result = await future;
      expect(result, isNull);
      expect(find.byType(ArchiveConfirmationDialog), findsNothing);
    });
  });

  group('UI/UX — Padrão Visual de Ação Destrutiva', () {
    testWidgets('botão de confirmação usa cor error (vermelho)', (
      tester,
    ) async {
      await openDialog(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar Arquivamento'),
      );
      final style = button.style!;
      final bgColor = style.backgroundColor!.resolve({});
      expect(bgColor, VeraProbColors.error);
    });

    testWidgets('ícone do título usa cor error', (tester) async {
      await openDialog(tester);

      final icon = tester.widget<Icon>(find.byIcon(Icons.archive_outlined));
      expect(icon.color, VeraProbColors.error);
    });

    testWidgets('exibe texto de advertência sobre consequências', (
      tester,
    ) async {
      await openDialog(tester);

      expect(
        find.textContaining('segredos de API serão revogados'),
        findsOneWidget,
      );
    });
  });

  group('A11y — Acessibilidade e Focus Trapping', () {
    testWidgets('autofocus no campo de motivo ao abrir', (tester) async {
      await openDialog(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
    });

    testWidgets('ícone possui semanticLabel para screen readers', (
      tester,
    ) async {
      await openDialog(tester);

      final icon = tester.widget<Icon>(find.byIcon(Icons.archive_outlined));
      expect(icon.semanticLabel, isNotNull);
      expect(icon.semanticLabel, isNotEmpty);
    });

    testWidgets('dialog contém ModalBarrier para focus trapping', (
      tester,
    ) async {
      await openDialog(tester);

      // Flutter's showDialog creates a ModalBarrier that traps focus
      expect(find.byType(ModalBarrier), findsWidgets);
    });

    testWidgets('Tab navega entre campos e botões sem escapar', (tester) async {
      await openDialog(tester);

      // Focus starts on TextFormField (autofocus)
      // Tab should move to Cancelar, then Confirmar, then back
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      // Dialog still visible — focus didn't escape
      expect(find.byType(ArchiveConfirmationDialog), findsOneWidget);
    });
  });

  group('Cobertura Complementar — dispose e static show()', () {
    testWidgets('static show() retorna Future<String?>', (tester) async {
      await tester.pumpWidget(buildApp());
      final ctx = tester.element(find.byType(Scaffold));
      final future = ArchiveConfirmationDialog.show(ctx);
      await tester.pumpAndSettle();

      expect(future, isA<Future<String?>>());

      // Clean up
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('controller é descartado sem leak ao fechar', (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // No exception thrown = dispose worked correctly
      expect(find.byType(ArchiveConfirmationDialog), findsNothing);
    });
  });
}
