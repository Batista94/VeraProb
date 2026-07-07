import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:veraprob/main.dart' as app;
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import '../helpers/failing_super_admin_repository.dart';

import '../helpers/superadmin_auth_helper.dart';
import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_navigation_helper.dart';
import '../helpers/superadmin_test_config.dart';
import '../helpers/superadmin_test_models.dart';
import '../helpers/superadmin_widget_helpers.dart';

/// Testes E2E para o cenário CT12: Arquivamento de Organização com Cascata.
///
/// Valida os fluxos de arquivamento de organizações pelo SuperAdmin,
/// incluindo Modal_Confirmação com justificativa, Cascata_Bloqueio de
/// todos os admins, ocultação de botões de ação, registro de auditoria,
/// atomicidade em caso de erro de rede e impedimento de duplicidade.
///
/// **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8**
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CT12: Arquivamento de Organização com Cascata', () {
    late TestOrgData testOrg;
    late TestOrgData testOrgAtomicity;
    late TestOrgData testOrgDuplicate;
    bool supabaseAvailable = false;

    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;

      // Criar org com 3 admins ativos para testes de cascata
      testOrg = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT12 Org Arquivar',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 3,
        pendingAdmins: 0,
      );

      // Criar org separada para teste de atomicidade (erro de rede)
      testOrgAtomicity = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT12 Org Atomicidade',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 0,
      );

      // Criar org separada para teste de arquivamento duplicado
      testOrgDuplicate = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT12 Org Duplicado',
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
      await SuperAdminDataFactory.cleanup(testOrg);
      await SuperAdminDataFactory.cleanup(testOrgAtomicity);
      await SuperAdminDataFactory.cleanup(testOrgDuplicate);
    });

    testWidgets(
      '4.1 Modal_Confirmação com campo de justificativa ao clicar Arquivar',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantDetail(
          tester,
          testOrg.orgName,
        );

        // Localizar o botão "Arquivar" no cabeçalho de detalhes da org
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
          // Fallback: buscar por texto "Arquivar" em qualquer botão
          buttonFinder = find.textContaining('Arquivar');
        }

        expect(
          buttonFinder,
          findsAtLeast(1),
          reason:
              'O botão "Arquivar" deve estar visível no cabeçalho da org '
              '(Req 4.1)',
        );

        await tester.tap(buttonFinder.first);
        await tester.pumpAndSettle();

        // Verificar que o Modal_Confirmação é exibido
        final dialog = find.byType(AlertDialog);
        final simpleDialog = find.byType(Dialog);
        expect(
          dialog.evaluate().isNotEmpty || simpleDialog.evaluate().isNotEmpty,
          isTrue,
          reason:
              'O Modal_Confirmação deve ser exibido ao clicar em '
              '"Arquivar" (Req 4.1)',
        );

        // Verificar que o modal contém um campo de justificativa (TextFormField)
        final justificationField = find.byType(TextFormField);
        expect(
          justificationField,
          findsAtLeast(1),
          reason:
              'O modal deve conter um campo de justificativa '
              '(TextFormField) (Req 4.1)',
        );

        // Cancelar para não alterar estado para próximos testes
        await SuperAdminWidgetHelpers.cancelModal(tester);
      },
    );

    testWidgets('4.2 Status muda para ARCHIVED no DB após confirmação', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // Verificar estado inicial
      final statusBefore = await SuperAdminDbVerifier.getOrgStatus(
        testOrg.orgId,
      );
      expect(
        statusBefore,
        equals('ACTIVE'),
        reason: 'Org deve estar ACTIVE antes do arquivamento',
      );

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrg.orgName,
      );

      // Clicar em "Arquivar"
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

      expect(buttonFinder, findsAtLeast(1));
      await tester.tap(buttonFinder.first);
      await tester.pumpAndSettle();

      // Preencher justificativa e confirmar
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Arquivamento para teste E2E CT12 — validação de cascata',
      );
      await SuperAdminWidgetHelpers.confirmModal(tester);

      // Aguardar processamento
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // Verificar no banco que o status mudou para ARCHIVED
      final statusAfter = await SuperAdminDbVerifier.getOrgStatus(
        testOrg.orgId,
      );
      expect(
        statusAfter,
        equals('ARCHIVED'),
        reason:
            'organization.status deve ser ARCHIVED após confirmação '
            '(Req 4.2)',
      );
    });

    testWidgets('4.3 Cascata_Bloqueio: todos admins com is_active=false e '
        'banned_until=infinity', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // A org já foi arquivada no teste 4.2.
      // Verificar que TODOS os admins estão bloqueados.

      // Verificar is_active=false para todos
      await SuperAdminDbVerifier.assertAllUsersActiveStatus(
        orgId: testOrg.orgId,
        expectedActive: false,
      );

      // Verificar banned_until não-nulo (infinity) para todos
      await SuperAdminDbVerifier.assertAllUsersBannedStatus(
        orgId: testOrg.orgId,
        shouldBeBanned: true,
      );

      // Verificar contagem: todos os 3 admins devem estar bloqueados
      final blockedCount = await SuperAdminDbVerifier.countBlockedUsers(
        testOrg.orgId,
      );
      expect(
        blockedCount,
        equals(testOrg.admins.length),
        reason:
            'O número de admins bloqueados deve ser igual ao total de '
            'admins da org (${testOrg.admins.length}) (Req 4.3)',
      );
    });

    testWidgets('4.4 Botões de ação ocultos na org arquivada', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // A org já está arquivada (teste 4.2).
      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrg.orgName,
      );
      await SuperAdminNavigationHelper.goToUsersTab(tester);

      // Verificar ausência do botão "Adicionar Administrador"
      final addAdminButton = find.byTooltip('Adicionar Administrador');
      final addAdminText = find.widgetWithText(FilledButton, 'Adicionar');
      final addAdminElevated = find.widgetWithText(ElevatedButton, 'Adicionar');
      expect(
        addAdminButton.evaluate().isEmpty &&
            addAdminText.evaluate().isEmpty &&
            addAdminElevated.evaluate().isEmpty,
        isTrue,
        reason:
            'O botão "Adicionar Administrador" deve estar oculto em org '
            'arquivada (Req 4.4)',
      );

      // Verificar ausência do botão "Editar"
      final editButton = find.byTooltip('Editar');
      final editButtonText = find.widgetWithText(IconButton, 'Editar');
      expect(
        editButton.evaluate().isEmpty && editButtonText.evaluate().isEmpty,
        isTrue,
        reason: 'O botão "Editar" deve estar oculto em org arquivada (Req 4.4)',
      );

      // Verificar ausência do botão "Inativar Usuário"
      final deactivateButton = find.byTooltip('Inativar Usuário');
      expect(
        deactivateButton,
        findsNothing,
        reason:
            'O botão "Inativar Usuário" deve estar oculto em org '
            'arquivada (Req 4.4)',
      );
    });

    testWidgets(
      '4.5 Registro de auditoria criado em system_audit_log com justificativa',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        // A org já foi arquivada no teste 4.2.
        // Verificar existência do registro de auditoria.
        final auditRecord = await SuperAdminDbVerifier.assertAuditLogExists(
          orgId: testOrg.orgId,
          eventType: 'ORG_ARCHIVED',
          reasonNotNull: true,
        );

        // Verificar que a justificativa contém o texto inserido
        final reason = auditRecord['reason'] as String;
        expect(
          reason,
          contains('CT12'),
          reason:
              'system_audit_log.reason deve conter a justificativa '
              'inserida pelo SuperAdmin (Req 4.5)',
        );
      },
    );

    testWidgets(
      '4.6 Botão de confirmação desabilitado com justificativa vazia',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        // Usar a org de atomicidade (ainda ACTIVE) para abrir o modal
        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantDetail(
          tester,
          testOrgAtomicity.orgName,
        );

        // Clicar em "Arquivar"
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

        expect(buttonFinder, findsAtLeast(1));
        await tester.tap(buttonFinder.first);
        await tester.pumpAndSettle();

        // Verificar que o botão de confirmação está desabilitado
        // (justificativa vazia)
        final isEnabled = SuperAdminWidgetHelpers.isConfirmButtonEnabled(
          tester,
        );
        expect(
          isEnabled,
          isFalse,
          reason:
              'O botão de confirmação deve estar desabilitado quando a '
              'justificativa está vazia (Req 4.6)',
        );

        // Cancelar o modal
        await SuperAdminWidgetHelpers.cancelModal(tester);
      },
    );

    testWidgets(
      '4.7 Atomicidade: estado não alterado parcialmente em erro de rede',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        // Capturar estado antes da operação
        final statusBefore = await SuperAdminDbVerifier.getOrgStatus(
          testOrgAtomicity.orgId,
        );
        expect(
          statusBefore,
          equals('ACTIVE'),
          reason: 'Org deve estar ACTIVE antes do teste de atomicidade',
        );

        final activeCountBefore = await SuperAdminDbVerifier.countActiveUsers(
          testOrgAtomicity.orgId,
        );

        // Simular falha de rede via repository override antes de iniciar o app
        app.testProviderOverrides = [
          superAdminRepositoryProvider.overrideWith((ref) {
            return FailingSuperAdminRepository(
              ref.watch(supabaseClientProvider),
              hmacRequestKey: SuperAdminTestConfig.hmacSecretKeyV1,
              failArchive: true,
            );
          }),
        ];

        try {
          await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
          await SuperAdminNavigationHelper.goToTenantDetail(
            tester,
            testOrgAtomicity.orgName,
          );

          // Clicar em "Arquivar"
          final archiveButton = find.byTooltip('Arquivar');
          final archiveButtonText = find.widgetWithText(
            FilledButton,
            'Arquivar',
          );
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

          expect(buttonFinder, findsAtLeast(1));
          await tester.tap(buttonFinder.first);
          await tester.pumpAndSettle();

          // Preencher justificativa
          await SuperAdminWidgetHelpers.fillJustification(
            tester,
            'Teste de atomicidade CT12 — simulação de falha de rede',
          );

          // Confirmar (a operação deve falhar por rede)
          await SuperAdminWidgetHelpers.confirmModal(tester);

          // Aguardar feedback de erro
          await SuperAdminWidgetHelpers.waitForSnackbar(
            tester,
            'Falha ao arquivar',
          );

          // Verificar que a aplicação não crashou
          expect(
            tester.takeException(),
            isNull,
            reason:
                'A aplicação não deve crashar em caso de falha de rede '
                '(Req 4.7)',
          );
        } finally {
          app.testProviderOverrides = [];
        }

        // Verificar que o estado no DB não mudou (atomicidade)
        final statusAfter = await SuperAdminDbVerifier.getOrgStatus(
          testOrgAtomicity.orgId,
        );
        expect(
          statusAfter,
          equals('ACTIVE'),
          reason:
              'organization.status deve permanecer ACTIVE quando ocorre '
              'erro de rede (atomicidade — Req 4.7)',
        );

        final activeCountAfter = await SuperAdminDbVerifier.countActiveUsers(
          testOrgAtomicity.orgId,
        );
        expect(
          activeCountAfter,
          equals(activeCountBefore),
          reason:
              'O número de admins ativos não deve mudar quando ocorre '
              'erro de rede (atomicidade — Req 4.7)',
        );
      },
    );

    testWidgets('4.8 Impedimento de arquivamento duplicado', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // Primeiro, arquivar a org de duplicado normalmente
      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgDuplicate.orgName,
      );

      // Clicar em "Arquivar"
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

      expect(buttonFinder, findsAtLeast(1));
      await tester.tap(buttonFinder.first);
      await tester.pumpAndSettle();

      // Preencher justificativa e confirmar
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Primeiro arquivamento CT12 — teste de duplicidade',
      );
      await SuperAdminWidgetHelpers.confirmModal(tester);

      // Aguardar processamento
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // Confirmar que a org está arquivada
      final status = await SuperAdminDbVerifier.getOrgStatus(
        testOrgDuplicate.orgId,
      );
      expect(status, equals('ARCHIVED'));

      // Agora tentar arquivar novamente — o botão "Arquivar" não deve
      // estar disponível (deve ter sido substituído por "Desarquivar")
      // OU se clicar, o sistema deve impedir a operação.

      // Recarregar a página de detalhes
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgDuplicate.orgName,
      );

      // Verificar que o botão "Arquivar" não está mais disponível
      final archiveButtonAfter = find.byTooltip('Arquivar');
      final archiveButtonTextAfter = find.widgetWithText(
        FilledButton,
        'Arquivar',
      );
      final archiveButtonElevatedAfter = find.widgetWithText(
        ElevatedButton,
        'Arquivar',
      );

      final archiveStillPresent =
          archiveButtonAfter.evaluate().isNotEmpty ||
          archiveButtonTextAfter.evaluate().isNotEmpty ||
          archiveButtonElevatedAfter.evaluate().isNotEmpty;

      if (archiveStillPresent) {
        // Se o botão ainda está presente, tentar clicar e verificar
        // que o sistema impede a operação duplicada
        Finder duplicateButtonFinder;
        if (archiveButtonAfter.evaluate().isNotEmpty) {
          duplicateButtonFinder = archiveButtonAfter;
        } else if (archiveButtonTextAfter.evaluate().isNotEmpty) {
          duplicateButtonFinder = archiveButtonTextAfter;
        } else {
          duplicateButtonFinder = archiveButtonElevatedAfter;
        }

        await tester.tap(duplicateButtonFinder.first);
        await tester.pumpAndSettle();

        // O sistema deve exibir mensagem de erro ou impedir a operação
        final errorText = find.textContaining('já arquivada');
        final errorSnackbar = find.byType(SnackBar);
        final blockDialog = find.byType(AlertDialog);

        expect(
          errorText.evaluate().isNotEmpty ||
              errorSnackbar.evaluate().isNotEmpty ||
              blockDialog.evaluate().isNotEmpty,
          isTrue,
          reason:
              'O sistema deve impedir arquivamento duplicado com '
              'mensagem de erro ou bloqueio (Req 4.8)',
        );
      } else {
        // O botão "Arquivar" foi removido/substituído — comportamento
        // correto: o sistema impede a operação por não oferecer o botão.
        // Verificar que "Desarquivar" está presente em seu lugar.
        final unarchiveButton = find.byTooltip('Desarquivar');
        final unarchiveText = find.textContaining('Desarquivar');

        expect(
          unarchiveButton.evaluate().isNotEmpty ||
              unarchiveText.evaluate().isNotEmpty,
          isTrue,
          reason:
              'O botão "Desarquivar" deve estar presente no lugar de '
              '"Arquivar" para org já arquivada (Req 4.8)',
        );
      }
    });
  });
}
