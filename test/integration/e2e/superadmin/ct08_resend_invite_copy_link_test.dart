import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:veraprob/main.dart' as app;
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

import '../helpers/failing_super_admin_repository.dart';
import '../helpers/superadmin_auth_helper.dart';
import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_navigation_helper.dart';
import '../helpers/superadmin_test_config.dart';
import '../helpers/superadmin_test_models.dart';
import '../helpers/superadmin_widget_helpers.dart';

/// Testes E2E para o cenário CT08: Reenviar Convite e Copiar Link.
///
/// Valida os fluxos de reenvio de convite e cópia de link para
/// administradores pendentes no painel SuperAdmin.
///
/// **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6**
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CT08: Reenviar Convite e Copiar Link', () {
    late TestOrgData testOrg;
    late TestOrgData testOrgNoPending;
    bool supabaseAvailable = false;
    bool edgeFunctionsAvailable = false;

    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;

      edgeFunctionsAvailable =
          await SuperAdminTestConfig.isEdgeFunctionsRunning();
      if (!edgeFunctionsAvailable) return;

      // Criar org com 1 admin ativo e 1 admin pendente para testes de botões
      testOrg = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT08 Org Pendente',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 1,
        pendingAdmins: 1,
      );

      // Criar org com apenas admins ativos (sem pendentes) para teste de ausência
      testOrgNoPending = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT08 Org Sem Pendente',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 0,
      );
    });

    tearDownAll(() async {
      try {
        await Supabase.instance.dispose();
      } catch (_) {}
      if (!supabaseAvailable) return;
      if (!edgeFunctionsAvailable) return;
      await SuperAdminDataFactory.cleanup(testOrg);
      await SuperAdminDataFactory.cleanup(testOrgNoPending);
    });

    testWidgets('2.1 Botão Copiar Link visível e habilitado para Admin_Pendente', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }
      if (!edgeFunctionsAvailable) {
        markTestSkipped(
          'Edge Functions não disponíveis (verifique supabase_edge_runtime_veraprob).',
        );
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrg.orgName,
      );
      await SuperAdminNavigationHelper.goToUsersTab(tester);

      // Verificar que o botão de copiar link (ícone prancheta) está visível
      final copyButton = find.byTooltip('Copiar link de convite');
      expect(
        copyButton,
        findsAtLeast(1),
        reason:
            'O botão "Copiar link de convite" deve estar visível para '
            'Admin_Pendente (Req 2.1)',
      );

      // Verificar que o botão está habilitado (IconButton com onPressed != null)
      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: copyButton, matching: find.byType(IconButton)).first,
      );
      expect(
        iconButton.onPressed,
        isNotNull,
        reason: 'O botão de Copiar Link deve estar habilitado (Req 2.1)',
      );
    });

    testWidgets(
      '2.2 Botão Reenviar Convite visível e habilitado para Admin_Pendente',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }
        if (!edgeFunctionsAvailable) {
          markTestSkipped(
            'Edge Functions não disponíveis (verifique supabase_edge_runtime_veraprob).',
          );
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantDetail(
          tester,
          testOrg.orgName,
        );
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Verificar que o botão de reenviar convite está visível
        final resendButton = find.byTooltip('Reenviar Convite');
        expect(
          resendButton,
          findsAtLeast(1),
          reason:
              'O botão "Reenviar Convite" deve estar visível para '
              'Admin_Pendente (Req 2.2)',
        );

        // Verificar que o botão está habilitado
        final iconButton = tester.widget<IconButton>(
          find
              .ancestor(of: resendButton, matching: find.byType(IconButton))
              .first,
        );
        expect(
          iconButton.onPressed,
          isNotNull,
          reason: 'O botão de Reenviar Convite deve estar habilitado (Req 2.2)',
        );
      },
    );

    testWidgets(
      '2.3 Ação de clipboard disparada sem erros de UI ao copiar link',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }
        if (!edgeFunctionsAvailable) {
          markTestSkipped(
            'Edge Functions não disponíveis (verifique supabase_edge_runtime_veraprob).',
          );
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantDetail(
          tester,
          testOrg.orgName,
        );
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Mock do clipboard channel para capturar a operação
        String? clipboardContent;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall methodCall) async {
            if (methodCall.method == 'Clipboard.setData') {
              final args = methodCall.arguments as Map<String, dynamic>;
              clipboardContent = args['text'] as String?;
            }
            return null;
          },
        );

        // Tocar no botão de copiar link
        final copyButton = find.byTooltip('Copiar link de convite');
        expect(copyButton, findsAtLeast(1));
        await tester.tap(copyButton.first);
        await tester.pumpAndSettle();

        // Verificar que nenhum erro de UI ocorreu
        expect(
          tester.takeException(),
          isNull,
          reason: 'A ação de clipboard não deve gerar erros de UI (Req 2.3)',
        );

        // Verificar que o snackbar de confirmação apareceu
        expect(
          find.text('Link de convite copiado.'),
          findsOneWidget,
          reason: 'Deve exibir snackbar confirmando cópia do link (Req 2.3)',
        );

        // Verificar que o clipboard recebeu um link válido
        expect(
          clipboardContent,
          isNotNull,
          reason: 'O clipboard deve receber o link de convite',
        );
        expect(
          clipboardContent,
          contains('accept-invite?token='),
          reason: 'O link copiado deve conter o token de convite',
        );

        // Limpar mock do clipboard
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      },
    );

    testWidgets('2.4 Feedback visual de sucesso ao reenviar convite', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }
      if (!edgeFunctionsAvailable) {
        markTestSkipped(
          'Edge Functions não disponíveis (verifique supabase_edge_runtime_veraprob).',
        );
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrg.orgName,
      );
      await SuperAdminNavigationHelper.goToUsersTab(tester);

      // Tocar no botão de reenviar convite
      final resendButton = find.byTooltip('Reenviar Convite');
      expect(resendButton, findsAtLeast(1));
      await tester.tap(resendButton.first);
      await tester.pumpAndSettle();

      // Preencher justificativa e confirmar
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Reenvio justificável',
      );
      await SuperAdminWidgetHelpers.confirmModal(tester);

      // Aguardar feedback visual de sucesso (snackbar)
      await SuperAdminWidgetHelpers.waitForSnackbar(
        tester,
        'Convite reenviado',
      );

      // Verificar que o snackbar de sucesso está visível
      final snackBar = find.byType(SnackBar);
      expect(
        snackBar,
        findsOneWidget,
        reason: 'Deve exibir feedback visual de sucesso ao reenviar (Req 2.4)',
      );
    });

    testWidgets('2.5 Ausência de botões quando não há convites pendentes', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }
      if (!edgeFunctionsAvailable) {
        markTestSkipped(
          'Edge Functions não disponíveis (verifique supabase_edge_runtime_veraprob).',
        );
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgNoPending.orgName,
      );
      await SuperAdminNavigationHelper.goToUsersTab(tester);

      // Verificar ausência do botão de copiar link
      final copyButton = find.byTooltip('Copiar link de convite');
      expect(
        copyButton,
        findsNothing,
        reason:
            'O botão "Copiar link de convite" NÃO deve estar presente '
            'quando não há convites pendentes (Req 2.5)',
      );
    });

    testWidgets('2.6 Exibição de erro em caso de falha de rede ao reenviar', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }
      if (!edgeFunctionsAvailable) {
        markTestSkipped(
          'Edge Functions não disponíveis (verifique supabase_edge_runtime_veraprob).',
        );
        return;
      }

      try {
        app.testProviderOverrides = [
          superAdminRepositoryProvider.overrideWith((ref) {
            return FailingSuperAdminRepository(
              ref.watch(supabaseClientProvider),
              hmacRequestKey: SuperAdminTestConfig.hmacSecretKeyV1,
              failResend: true,
            );
          }),
        ];

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantDetail(
          tester,
          testOrg.orgName,
        );
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Tocar no botão de reenviar convite
        final resendButton = find.byTooltip('Reenviar Convite');
        expect(resendButton, findsAtLeast(1));
        await tester.tap(resendButton.first);
        await tester.pumpAndSettle();

        // Preencher justificativa e confirmar
        await SuperAdminWidgetHelpers.fillJustification(
          tester,
          'Reenvio falho',
        );
        await SuperAdminWidgetHelpers.confirmModal(tester);

        // Aguardar feedback de erro (snackbar com mensagem de erro)
        await SuperAdminWidgetHelpers.waitForSnackbar(
          tester,
          'Falha ao reenviar',
        );

        // Verificar que a aplicação não crashou
        expect(
          tester.takeException(),
          isNull,
          reason:
              'A aplicação não deve crashar em caso de falha de rede (Req 2.6)',
        );

        // Verificar que o snackbar de erro está visível
        final errorSnackbar = find.byType(SnackBar);
        expect(
          errorSnackbar,
          findsOneWidget,
          reason:
              'Deve exibir mensagem de erro ao usuário em caso de falha '
              'de rede (Req 2.6)',
        );
      } finally {
        app.testProviderOverrides = [];
      }
    });
  });
}
