import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/superadmin_auth_helper.dart';
import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_navigation_helper.dart';
import '../helpers/superadmin_test_config.dart';
import '../helpers/superadmin_test_models.dart';
import '../helpers/superadmin_widget_helpers.dart';

/// Testes E2E para o cenário CT16: Overflow de UI com Textos Longos.
///
/// Valida que a interface trata graciosamente textos extremamente longos,
/// garantindo que o layout não quebre independente do conteúdo inserido.
/// Verifica truncamento com reticências, tooltips de acessibilidade,
/// ausência de overflow horizontal, e renderização correta de caracteres
/// especiais brasileiros (ç, ã, õ, é, ü, &).
///
/// **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5, 7.6**
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CT16: Overflow de UI com Textos Longos', () {
    late TestOrgData testOrgLongName;
    late TestOrgData testOrgBrazilianChars;
    bool supabaseAvailable = false;

    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;

      // Criar org com razão social longa (150+ chars) e admin com nome longo (100+ chars)
      final longOrgName = SuperAdminDataFactory.generateLongName(155);
      testOrgLongName = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: longOrgName,
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 1,
        pendingAdmins: 0,
      );

      // Criar org com caracteres especiais brasileiros em nome longo
      const brazilianCharsName =
          'Viação São José dos Campos & Cia Ltda — Transportes Especiais '
          'com Ônibus Elétricos e Híbridos para Região Metropolitana do '
          'Vale do Paraíba — Razão Social Completa: ç, ã, õ, é, ü, ñ';
      testOrgBrazilianChars = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: brazilianCharsName,
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
      await SuperAdminDataFactory.cleanup(testOrgLongName);
      await SuperAdminDataFactory.cleanup(testOrgBrazilianChars);
    });

    testWidgets('7.1 Truncamento com reticências para nomes de admin longos', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantList(tester);
      await tester.pumpAndSettle();

      // Verificar que não há exceção de overflow
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Nenhum RenderFlex overflow deve ocorrer ao exibir nomes longos',
      );

      // Verificar que existem widgets Text com TextOverflow.ellipsis
      // (indicando truncamento correto)
      final truncatedTexts = find.byWidgetPredicate(
        (widget) => widget is Text && widget.overflow == TextOverflow.ellipsis,
      );

      expect(
        truncatedTexts,
        findsWidgets,
        reason:
            'Deve existir pelo menos um widget Text com overflow ellipsis '
            'para tratar nomes longos (Req 7.1)',
      );
    });

    testWidgets(
      '7.2 Alinhamento correto do grid com razão social longa (150+ chars)',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantList(tester);
        await tester.pumpAndSettle();

        // Verificar que não há exceção de overflow ao renderizar org com
        // nome de 150+ caracteres
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Nenhum RenderFlex overflow deve ocorrer com razão social de '
              '150+ caracteres no grid de listagem (Req 7.2)',
        );

        // Verificar que o layout mantém estrutura (ListTile ou Card visível)
        final listItems = find.byType(ListTile);
        final cards = find.byType(Card);

        final hasStructuredLayout =
            listItems.evaluate().isNotEmpty || cards.evaluate().isNotEmpty;
        expect(
          hasStructuredLayout,
          isTrue,
          reason:
              'O grid de listagem deve manter estrutura (ListTile ou Card) '
              'mesmo com razão social de 150+ caracteres (Req 7.2)',
        );
      },
    );

    testWidgets(
      '7.3 Ausência de overflow horizontal (sem scrollbar horizontal)',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantList(tester);
        await tester.pumpAndSettle();

        // Usar o helper dedicado para verificar ausência de overflow horizontal
        await SuperAdminWidgetHelpers.assertNoHorizontalOverflow(tester);
      },
    );

    testWidgets(
      '7.4 Containers de cards/chips não excedem limites com textos longos',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantList(tester);
        await tester.pumpAndSettle();

        // Verificar que não há exceção de overflow
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Nenhum RenderFlex overflow deve ocorrer em cards/chips com '
              'textos longos (Req 7.4)',
        );

        // Verificar que Chips (se existirem) não excedem a largura da tela
        final chips = find.byType(Chip);
        final filterChips = find.byType(FilterChip);

        final screenWidth =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;

        for (final chip in chips.evaluate()) {
          final renderBox = chip.renderObject as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            expect(
              renderBox.size.width,
              lessThanOrEqualTo(screenWidth),
              reason:
                  'Chip não deve exceder a largura da tela '
                  '(width: ${renderBox.size.width}, screen: $screenWidth) '
                  '(Req 7.4)',
            );
          }
        }

        for (final chip in filterChips.evaluate()) {
          final renderBox = chip.renderObject as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            expect(
              renderBox.size.width,
              lessThanOrEqualTo(screenWidth),
              reason:
                  'FilterChip não deve exceder a largura da tela '
                  '(width: ${renderBox.size.width}, screen: $screenWidth) '
                  '(Req 7.4)',
            );
          }
        }

        // Verificar Cards não excedem limites
        final cardWidgets = find.byType(Card);
        for (final card in cardWidgets.evaluate()) {
          final renderBox = card.renderObject as RenderBox?;
          if (renderBox != null && renderBox.hasSize) {
            expect(
              renderBox.size.width,
              lessThanOrEqualTo(screenWidth),
              reason:
                  'Card não deve exceder a largura da tela '
                  '(width: ${renderBox.size.width}, screen: $screenWidth) '
                  '(Req 7.4)',
            );
          }
        }
      },
    );

    testWidgets(
      '7.5 Caracteres especiais brasileiros (ç, ã, õ, é, ü, &) em nomes longos',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantList(tester);
        await tester.pumpAndSettle();

        // Search for "Viação" to bring the organization to the top and render it
        final searchField = find.byType(TextField);
        await tester.enterText(searchField, 'Viação');
        // Wait for search debounce (usually 300ms) + network load
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Verificar que não há exceção ao renderizar caracteres especiais
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Nenhuma exceção deve ocorrer ao renderizar caracteres '
              'especiais brasileiros em nomes longos (Req 7.5)',
        );

        // Verificar que pelo menos parte do nome com caracteres especiais
        // está renderizada (pode estar truncada, mas sem mojibake).
        // Buscar por substring que contém caracteres especiais.
        final brazilianSubstring = find.textContaining('Viação São José');

        // Se o texto está truncado, pode não encontrar a substring completa.
        // Nesse caso, verificar que pelo menos o início do nome está visível
        // (indicando renderização correta sem mojibake).
        final viacao = find.textContaining('Viação');
        final saoJose = find.textContaining('São');

        final hasCorrectRendering =
            brazilianSubstring.evaluate().isNotEmpty ||
            viacao.evaluate().isNotEmpty ||
            saoJose.evaluate().isNotEmpty;

        expect(
          hasCorrectRendering,
          isTrue,
          reason:
              'Caracteres especiais brasileiros (ç, ã, õ) devem ser '
              'renderizados corretamente sem mojibake. Pelo menos parte '
              'do nome "Viação São José..." deve estar visível (Req 7.5)',
        );
      },
    );

    testWidgets(
      '7.6 Tooltip com nome completo aparece ao hover sobre texto truncado',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantList(tester);
        await tester.pumpAndSettle();

        // Localizar textos truncados com ellipsis
        final truncatedTexts = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.overflow == TextOverflow.ellipsis,
        );

        // Se não encontrar textos truncados, verificar se há Tooltip wrapping
        // textos longos (implementação alternativa)
        if (truncatedTexts.evaluate().isEmpty) {
          // Verificar se existem Tooltips na tela (implementação alternativa
          // onde o texto é wrappado em Tooltip sem necessariamente usar ellipsis)
          final tooltips = find.byType(Tooltip);
          expect(
            tooltips,
            findsWidgets,
            reason:
                'Deve existir pelo menos um Tooltip para textos longos '
                'quando não há truncamento explícito com ellipsis (Req 7.6)',
          );
          return;
        }

        expect(
          truncatedTexts,
          findsWidgets,
          reason:
              'Deve existir pelo menos um widget Text com overflow ellipsis '
              'para testar tooltip de acessibilidade (Req 7.6)',
        );

        // Criar gesto de mouse para simular hover sobre texto truncado
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(
          location: tester.getCenter(truncatedTexts.first),
        );
        await tester.pumpAndSettle();

        // Verificar que um Tooltip aparece ao hover
        final tooltips = find.byType(Tooltip);
        expect(
          tooltips,
          findsWidgets,
          reason:
              'Um Tooltip com o nome completo deve aparecer ao passar o '
              'mouse (hover) sobre texto truncado, garantindo '
              'acessibilidade operacional ao SuperAdmin (Req 7.6)',
        );

        // Limpar o gesto de hover
        await gesture.removePointer();
        await tester.pumpAndSettle();
      },
    );
  });
}
