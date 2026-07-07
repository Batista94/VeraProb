import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/superadmin_auth_helper.dart';
import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_navigation_helper.dart';
import '../helpers/superadmin_test_config.dart';
import '../helpers/superadmin_test_models.dart';
import '../helpers/superadmin_widget_helpers.dart';

/// Testes E2E para o cenário CT15: Veto de Justificativa Vazia.
///
/// Valida que operações críticas (arquivar, desarquivar) nunca podem ser
/// executadas sem justificativa textual válida (≥10 caracteres não-whitespace).
/// O botão de confirmação deve permanecer desabilitado enquanto a justificativa
/// não atender aos critérios mínimos, e nenhuma chamada de API deve ser
/// disparada via bypass de teclado (Enter) enquanto o botão estiver desabilitado.
///
/// **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6**
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CT15: Veto de Justificativa Vazia', () {
    late TestOrgData testOrg;
    bool supabaseAvailable = false;

    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;

      // Criar org ativa para testes de modal de arquivamento
      testOrg = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT15 Org Veto Justificativa',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 1,
        pendingAdmins: 0,
      );
    });

    tearDownAll(() async {
      try {
        await Supabase.instance.dispose();
      } catch (_) {}
      if (!supabaseAvailable) return;
      await SuperAdminDataFactory.cleanup(testOrg);
    });

    /// Helper para abrir o modal de arquivamento da org de teste.
    ///
    /// Navega até o detalhe da org e clica no botão "Arquivar" para
    /// abrir o Modal_Confirmação com campo de justificativa.
    Future<void> openArchiveModal(WidgetTester tester) async {
      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrg.orgName,
      );

      // Localizar o botão "Arquivar"
      final archiveButton = find.byTooltip('Arquivar');
      final archiveButtonText = find.widgetWithText(FilledButton, 'Arquivar');
      final archiveButtonElevated = find.widgetWithText(
        ElevatedButton,
        'Arquivar',
      );

      Finder buttonFinder;
      if (archiveButton.evaluate().isNotEmpty) {
        buttonFinder = archiveButton;
      } else if (archiveButtonText.evaluate().isNotEmpty) {
        buttonFinder = archiveButtonText;
      } else if (archiveButtonElevated.evaluate().isNotEmpty) {
        buttonFinder = archiveButtonElevated;
      } else {
        buttonFinder = find.textContaining('Arquivar');
      }

      expect(
        buttonFinder,
        findsAtLeast(1),
        reason:
            'O botão "Arquivar" deve estar visível no cabeçalho da org '
            '(CT15 setup)',
      );

      await tester.tap(buttonFinder.first);
      await tester.pumpAndSettle();
    }

    testWidgets('6.1 Botão de confirmação inicia desabilitado ao abrir modal', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await openArchiveModal(tester);

      // Verificar que o botão de confirmação está desabilitado
      final isEnabled = SuperAdminWidgetHelpers.isConfirmButtonEnabled(tester);
      expect(
        isEnabled,
        isFalse,
        reason:
            'O botão de confirmação deve iniciar desabilitado quando o '
            'modal é aberto (Req 6.1)',
      );

      // Cancelar para resetar estado
      await SuperAdminWidgetHelpers.cancelModal(tester);
    });

    testWidgets('6.2 Botão permanece desabilitado com campo vazio', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await openArchiveModal(tester);

      // Preencher com string vazia (simula foco e desfoco sem digitar)
      await SuperAdminWidgetHelpers.fillJustification(tester, '');
      await tester.pump();

      // Verificar que o botão permanece desabilitado
      final isEnabled = SuperAdminWidgetHelpers.isConfirmButtonEnabled(tester);
      expect(
        isEnabled,
        isFalse,
        reason:
            'O botão de confirmação deve permanecer desabilitado com '
            'campo vazio (Req 6.2)',
      );

      // Cancelar para resetar estado
      await SuperAdminWidgetHelpers.cancelModal(tester);
    });

    testWidgets(
      '6.3 Botão habilita ao digitar texto válido (≥10 chars não-whitespace)',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await openArchiveModal(tester);

        // Preencher com texto válido (≥10 caracteres não-whitespace)
        await SuperAdminWidgetHelpers.fillJustification(
          tester,
          'Justificativa válida para teste CT15',
        );

        // Verificar que o botão está habilitado
        final isEnabled = SuperAdminWidgetHelpers.isConfirmButtonEnabled(
          tester,
        );
        expect(
          isEnabled,
          isTrue,
          reason:
              'O botão de confirmação deve estar habilitado quando a '
              'justificativa possui ≥10 chars não-whitespace (Req 6.3)',
        );

        // Cancelar para resetar estado
        await SuperAdminWidgetHelpers.cancelModal(tester);
      },
    );

    testWidgets('6.4 Botão volta a desabilitar ao limpar campo', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await openArchiveModal(tester);

      // Preencher com texto válido primeiro
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Texto válido para habilitar botão',
      );

      // Verificar que habilitou
      final isEnabledBefore = SuperAdminWidgetHelpers.isConfirmButtonEnabled(
        tester,
      );
      expect(
        isEnabledBefore,
        isTrue,
        reason: 'Botão deve estar habilitado com texto válido (setup 6.4)',
      );

      // Limpar o campo (substituir por string vazia)
      await SuperAdminWidgetHelpers.fillJustification(tester, '');

      // Verificar que o botão voltou a ficar desabilitado
      final isEnabledAfter = SuperAdminWidgetHelpers.isConfirmButtonEnabled(
        tester,
      );
      expect(
        isEnabledAfter,
        isFalse,
        reason:
            'O botão de confirmação deve voltar a ficar desabilitado '
            'ao limpar o campo de justificativa (Req 6.4)',
      );

      // Cancelar para resetar estado
      await SuperAdminWidgetHelpers.cancelModal(tester);
    });

    testWidgets(
      '6.5 Botão permanece desabilitado com apenas espaços em branco',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await openArchiveModal(tester);

        // Preencher com apenas espaços em branco (vários tipos de whitespace)
        await SuperAdminWidgetHelpers.fillJustification(
          tester,
          '                    ', // 20 espaços
        );

        // Verificar que o botão permanece desabilitado (trim validation)
        final isEnabled = SuperAdminWidgetHelpers.isConfirmButtonEnabled(
          tester,
        );
        expect(
          isEnabled,
          isFalse,
          reason:
              'O botão de confirmação deve permanecer desabilitado quando '
              'a justificativa contém apenas espaços em branco — trim '
              'validation (Req 6.5)',
        );

        // Testar também com tabs e newlines
        await SuperAdminWidgetHelpers.fillJustification(
          tester,
          '\t\t\t   \n\n   ', // tabs, espaços e newlines
        );

        final isEnabledWithMixedWhitespace =
            SuperAdminWidgetHelpers.isConfirmButtonEnabled(tester);
        expect(
          isEnabledWithMixedWhitespace,
          isFalse,
          reason:
              'O botão deve permanecer desabilitado com mix de whitespace '
              '(tabs, newlines, espaços) (Req 6.5)',
        );

        // Cancelar para resetar estado
        await SuperAdminWidgetHelpers.cancelModal(tester);
      },
    );

    testWidgets('6.6 Enter não dispara API enquanto botão desabilitado', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await openArchiveModal(tester);

      // Verificar que o botão está desabilitado (campo vazio)
      final isEnabledBefore = SuperAdminWidgetHelpers.isConfirmButtonEnabled(
        tester,
      );
      expect(
        isEnabledBefore,
        isFalse,
        reason: 'Botão deve estar desabilitado antes do teste de Enter',
      );

      // Localizar o campo de justificativa e dar foco
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
        textFieldFinder = find.byType(TextFormField);
      }

      expect(
        textFieldFinder,
        findsAtLeast(1),
        reason: 'Campo de justificativa deve estar visível no modal',
      );

      // Dar foco ao campo
      await tester.tap(textFieldFinder.first);
      await tester.pump();

      // Simular pressionar Enter via teclado
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Verificar que o modal ainda está visível (Enter não disparou API)
      final dialogStillVisible =
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(Dialog).evaluate().isNotEmpty;
      expect(
        dialogStillVisible,
        isTrue,
        reason:
            'O modal deve permanecer visível após pressionar Enter com '
            'botão desabilitado — nenhuma API deve ser disparada (Req 6.6)',
      );

      // Verificar que o botão ainda está desabilitado
      final isEnabledAfter = SuperAdminWidgetHelpers.isConfirmButtonEnabled(
        tester,
      );
      expect(
        isEnabledAfter,
        isFalse,
        reason:
            'O botão deve permanecer desabilitado após tentativa de '
            'bypass via Enter (Req 6.6)',
      );

      // Também testar com TextInputAction.done
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Modal ainda deve estar visível
      final dialogStillVisibleAfterDone =
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(Dialog).evaluate().isNotEmpty;
      expect(
        dialogStillVisibleAfterDone,
        isTrue,
        reason:
            'O modal deve permanecer visível após TextInputAction.done '
            'com botão desabilitado (Req 6.6)',
      );

      // Cancelar para resetar estado
      await SuperAdminWidgetHelpers.cancelModal(tester);
    });
  });
}
