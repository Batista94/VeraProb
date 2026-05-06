import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'superadmin_test_config.dart';

/// Helpers para interação com widgets específicos do SuperAdmin.
///
/// Encapsula operações comuns em modais de confirmação, snackbars,
/// validação de overflow e retry para timing issues.
///
/// Usado pelos testes E2E para:
/// - Preencher justificativas em modais de operações críticas (CT12, CT13, CT15)
/// - Confirmar/cancelar modais de confirmação
/// - Verificar estado de habilitação do botão de confirmação (veto de justificativa)
/// - Aguardar snackbars de feedback
/// - Verificar ausência de overflow horizontal (CT16)
///
/// **Validates: Requirements 4.1, 4.6, 5.1, 5.6, 6.1, 6.2**
abstract class SuperAdminWidgetHelpers {
  /// Preenche o campo de justificativa no modal de confirmação.
  ///
  /// Localiza o [TextFormField] dentro do [AlertDialog] ou [Dialog] visível,
  /// limpa o conteúdo existente e insere [text]. Executa `pump()` para
  /// processar a mudança de estado do formulário.
  ///
  /// Pré-condição: um modal com campo de justificativa está visível.
  ///
  /// Lança [TestFailure] se nenhum TextFormField for encontrado no modal.
  static Future<void> fillJustification(
    WidgetTester tester,
    String text,
  ) async {
    // Localizar o TextFormField dentro do Dialog visível.
    final dialogFinder = find.byType(AlertDialog);
    final simpledialogFinder = find.byType(Dialog);

    Finder textFieldFinder;

    if (dialogFinder.evaluate().isNotEmpty) {
      textFieldFinder = find.descendant(
        of: dialogFinder,
        matching: find.byType(TextFormField),
      );
    } else if (simpledialogFinder.evaluate().isNotEmpty) {
      textFieldFinder = find.descendant(
        of: simpledialogFinder,
        matching: find.byType(TextFormField),
      );
    } else {
      // Fallback: buscar qualquer TextFormField visível (pode estar em
      // um widget customizado de modal).
      textFieldFinder = find.byType(TextFormField);
    }

    expect(
      textFieldFinder,
      findsAtLeast(1),
      reason:
          'O campo de justificativa (TextFormField) deve estar visível no modal',
    );

    // Limpar o campo e inserir o novo texto.
    await tester.enterText(textFieldFinder.first, text);
    await tester.pump();
  }

  /// Clica no botão de confirmação do modal.
  ///
  /// Busca um [FilledButton] ou [ElevatedButton] cujo texto contenha
  /// "Confirmar" (case-insensitive via widget predicate). Toca no botão
  /// e aguarda `pumpAndSettle` para processar a operação.
  ///
  /// Pré-condição: o modal de confirmação está visível com botão habilitado.
  ///
  /// Lança [TestFailure] se o botão de confirmação não for encontrado.
  static Future<void> confirmModal(WidgetTester tester) async {
    final confirmButton = _findConfirmButton();

    expect(
      confirmButton,
      findsAtLeast(1),
      reason:
          'O botão de confirmação ("Confirmar...") deve estar visível no modal',
    );

    await tester.tap(confirmButton.first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }

  /// Clica no botão de cancelamento do modal.
  ///
  /// Busca um [TextButton] ou [OutlinedButton] cujo texto contenha
  /// "Cancelar". Toca no botão e aguarda `pumpAndSettle`.
  ///
  /// Pré-condição: o modal de confirmação está visível.
  ///
  /// Lança [TestFailure] se o botão de cancelamento não for encontrado.
  static Future<void> cancelModal(WidgetTester tester) async {
    final cancelButton = _findCancelButton();

    expect(
      cancelButton,
      findsAtLeast(1),
      reason: 'O botão "Cancelar" deve estar visível no modal',
    );

    await tester.tap(cancelButton.first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }

  /// Verifica se o botão de confirmação está habilitado.
  ///
  /// Retorna `true` se o botão de confirmação (FilledButton/ElevatedButton
  /// com texto "Confirmar") possui `onPressed != null`.
  /// Retorna `false` se o botão está desabilitado (`onPressed == null`).
  ///
  /// Pré-condição: o modal de confirmação está visível.
  ///
  /// Lança [TestFailure] se o botão de confirmação não for encontrado.
  static bool isConfirmButtonEnabled(WidgetTester tester) {
    // Tentar encontrar FilledButton com "Confirmar".
    final filledButtons = find.byWidgetPredicate(
      (widget) =>
          widget is FilledButton &&
          _hasTextDescendant(widget, tester, 'Confirmar'),
    );

    if (filledButtons.evaluate().isNotEmpty) {
      final button = tester.widget<FilledButton>(filledButtons.first);
      return button.onPressed != null;
    }

    // Fallback: ElevatedButton com "Confirmar".
    final elevatedButtons = find.byWidgetPredicate(
      (widget) =>
          widget is ElevatedButton &&
          _hasTextDescendant(widget, tester, 'Confirmar'),
    );

    if (elevatedButtons.evaluate().isNotEmpty) {
      final button = tester.widget<ElevatedButton>(elevatedButtons.first);
      return button.onPressed != null;
    }

    fail(
      'Botão de confirmação ("Confirmar") não encontrado. '
      'Verifique se o modal está visível.',
    );
  }

  /// Aguarda um [SnackBar] contendo [text] aparecer na tela.
  ///
  /// Usa [retryUntil] para aguardar até que o SnackBar com o texto
  /// especificado seja renderizado. Útil para verificar feedback de
  /// sucesso/erro após operações assíncronas.
  ///
  /// Lança [TestFailure] se o SnackBar não aparecer dentro do timeout.
  static Future<void> waitForSnackbar(WidgetTester tester, String text) async {
    await retryUntil(
      tester,
      () async {
        await tester.pump(const Duration(milliseconds: 100));
        final snackBarFinder = find.byType(SnackBar);
        if (snackBarFinder.evaluate().isEmpty) return false;

        final textFinder = find.descendant(
          of: snackBarFinder,
          matching: find.textContaining(text),
        );
        return textFinder.evaluate().isNotEmpty;
      },
      timeout: SuperAdminTestConfig.defaultTimeout,
      interval: const Duration(milliseconds: 250),
    );
  }

  /// Verifica ausência de overflow horizontal na tela atual.
  ///
  /// Realiza duas verificações:
  /// 1. Verifica que `tester.takeException()` é null (nenhum RenderFlex
  ///    overflow error ocorreu durante o último frame).
  /// 2. Verifica que não existe um [Scrollable] horizontal inesperado
  ///    na árvore de widgets (exceto dentro de componentes que
  ///    legitimamente usam scroll horizontal, como TabBar).
  ///
  /// Usado pelo CT16 para garantir que textos longos não quebram o layout.
  static Future<void> assertNoHorizontalOverflow(WidgetTester tester) async {
    // Verificar que nenhum RenderFlex overflow ocorreu.
    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason:
          'Nenhum RenderFlex overflow deve ocorrer. '
          'Exceção encontrada: $exception',
    );

    // Verificar ausência de Scrollable horizontal inesperado.
    // Scrollables horizontais legítimos (TabBar, ListView horizontal)
    // são filtrados verificando se estão dentro de componentes conhecidos.
    final horizontalScrollables = find.byWidgetPredicate((widget) {
      if (widget is Scrollable && widget.axis == Axis.horizontal) {
        // Permitir scrollables dentro de TabBar (legítimo).
        return true;
      }
      return false;
    });

    // Se encontrar scrollables horizontais, verificar se são legítimos
    // (dentro de TabBar, PageView, etc.).
    for (final element in horizontalScrollables.evaluate()) {
      final widget = element.widget;
      // Verificar se o Scrollable está dentro de um TabBar ou PageView.
      final isInsideTabBar = find
          .ancestor(of: find.byWidget(widget), matching: find.byType(TabBar))
          .evaluate()
          .isNotEmpty;
      final isInsidePageView = find
          .ancestor(of: find.byWidget(widget), matching: find.byType(PageView))
          .evaluate()
          .isNotEmpty;
      final isInsideListView = find
          .ancestor(
            of: find.byWidget(widget),
            matching: find.byWidgetPredicate(
              (w) => w is ListView && w.scrollDirection == Axis.horizontal,
            ),
          )
          .evaluate()
          .isNotEmpty;

      if (!isInsideTabBar && !isInsidePageView && !isInsideListView) {
        fail(
          'Scrollable horizontal inesperado encontrado fora de '
          'componentes legítimos (TabBar, PageView, ListView horizontal). '
          'Isso indica overflow horizontal no layout.',
        );
      }
    }
  }

  /// Aguarda até que [condition] retorne `true` ou [timeout] seja atingido.
  ///
  /// Executa `pump()` entre cada verificação para permitir que frames
  /// sejam processados. Útil para aguardar operações assíncronas que
  /// atualizam a UI (snackbars, navegação, loading states).
  ///
  /// Parâmetros:
  /// - [tester]: O WidgetTester do teste atual.
  /// - [condition]: Função assíncrona que retorna `true` quando a condição
  ///   desejada é satisfeita.
  /// - [timeout]: Tempo máximo de espera (padrão: 10 segundos).
  /// - [interval]: Intervalo entre verificações (padrão: 500ms).
  ///
  /// Lança [TestFailure] se o timeout for atingido sem a condição ser
  /// satisfeita.
  static Future<void> retryUntil(
    WidgetTester tester,
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      final result = await condition();
      if (result) {
        stopwatch.stop();
        return;
      }

      // Pump para processar frames pendentes.
      await tester.pump(interval);
    }

    stopwatch.stop();
    fail(
      'retryUntil: condição não satisfeita após ${timeout.inSeconds}s. '
      'Verifique se a operação assíncrona completou ou se o widget '
      'esperado foi renderizado.',
    );
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  /// Encontra o botão de confirmação no modal.
  ///
  /// Busca por FilledButton ou ElevatedButton cujo texto contenha
  /// "Confirmar" (parcial, para cobrir variações como
  /// "Confirmar Arquivamento", "Confirmar Desarquivamento", etc.).
  static Finder _findConfirmButton() {
    // Primeiro tentar FilledButton com texto contendo "Confirmar".
    final filledButton = find.widgetWithText(FilledButton, 'Confirmar');
    if (filledButton.evaluate().isNotEmpty) return filledButton;

    // Tentar com textContaining para variações.
    final filledContaining = find.byWidgetPredicate(
      (widget) => widget is FilledButton,
    );
    // Buscar descendente com texto contendo "Confirmar".
    final filledWithText = find.descendant(
      of: filledContaining,
      matching: find.textContaining('Confirmar'),
    );
    if (filledWithText.evaluate().isNotEmpty) {
      // Retornar o botão pai.
      return find.ancestor(
        of: find.textContaining('Confirmar'),
        matching: find.byType(FilledButton),
      );
    }

    // Fallback: ElevatedButton.
    final elevatedButton = find.widgetWithText(ElevatedButton, 'Confirmar');
    if (elevatedButton.evaluate().isNotEmpty) return elevatedButton;

    final elevatedContaining = find.ancestor(
      of: find.textContaining('Confirmar'),
      matching: find.byType(ElevatedButton),
    );
    if (elevatedContaining.evaluate().isNotEmpty) return elevatedContaining;

    // Último fallback: qualquer botão com "Confirmar".
    return find.widgetWithText(TextButton, 'Confirmar');
  }

  /// Encontra o botão de cancelamento no modal.
  static Finder _findCancelButton() {
    // TextButton com "Cancelar".
    final textButton = find.widgetWithText(TextButton, 'Cancelar');
    if (textButton.evaluate().isNotEmpty) return textButton;

    // OutlinedButton com "Cancelar".
    final outlinedButton = find.widgetWithText(OutlinedButton, 'Cancelar');
    if (outlinedButton.evaluate().isNotEmpty) return outlinedButton;

    // Fallback: qualquer botão com "Cancelar".
    return find.textContaining('Cancelar');
  }

  /// Verifica se um widget possui um descendente Text contendo [text].
  ///
  /// Usado internamente para identificar botões pelo texto do label.
  static bool _hasTextDescendant(
    Widget widget,
    WidgetTester tester,
    String text,
  ) {
    final widgetFinder = find.byWidget(widget);
    if (widgetFinder.evaluate().isEmpty) return false;

    final textFinder = find.descendant(
      of: widgetFinder,
      matching: find.textContaining(text),
    );
    return textFinder.evaluate().isNotEmpty;
  }
}
