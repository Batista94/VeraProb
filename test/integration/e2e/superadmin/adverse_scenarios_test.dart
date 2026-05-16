import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/superadmin_auth_helper.dart';
import '../helpers/superadmin_data_factory.dart';
import '../helpers/superadmin_db_verifier.dart';
import '../helpers/superadmin_navigation_helper.dart';
import '../helpers/superadmin_test_config.dart';
import '../helpers/superadmin_test_models.dart';
import '../helpers/superadmin_widget_helpers.dart';

/// Testes E2E para cenários adversos e condições de corrida.
///
/// Valida o comportamento do sistema sob condições adversas incluindo:
/// - Race conditions (arquivamento durante edição concorrente)
/// - Erros de rede com retry
/// - Idempotência de double-click
/// - Navegação durante operação em andamento
/// - Expiração de token com anti "Flash de Dados"
/// - Race condition em revogação de convite já aceito
/// - Rejeição de CNPJ duplicado
///
/// **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 9.6**
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Cenários Adversos e Condições de Corrida', () {
    late TestOrgData testOrgRaceCondition;
    late TestOrgData testOrgNetworkError;
    late TestOrgData testOrgDoubleClick;
    late TestOrgData testOrgNavigation;
    late TestOrgData testOrgTokenExpiry;
    late TestOrgData testOrgRevokeRace;
    late TestOrgData testOrgCnpjDuplicate;
    bool supabaseAvailable = false;

    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;

      // 8.1: Org para teste de race condition (arquivar durante edição)
      testOrgRaceCondition = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'Adverse Race Condition Org',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 0,
      );

      // 8.2: Org para teste de erro de rede com retry
      testOrgNetworkError = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'Adverse Network Error Org',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 0,
      );

      // 8.3: Org para teste de double-click idempotência
      testOrgDoubleClick = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'Adverse Double Click Org',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 0,
      );

      // 8.4: Org para teste de navegação durante operação
      testOrgNavigation = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'Adverse Navigation Org',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 0,
      );

      // 8.5: Org para teste de token expiry
      testOrgTokenExpiry = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'Adverse Token Expiry Org',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 1,
        pendingAdmins: 0,
      );

      // 8.6: Org para teste de revogação de convite já aceito
      testOrgRevokeRace = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'Adverse Revoke Race Org',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 1,
        pendingAdmins: 1,
      );

      // 9.6: Org para teste de CNPJ duplicado
      testOrgCnpjDuplicate = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'Adverse CNPJ Duplicate Org',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 1,
        pendingAdmins: 0,
      );
    });

    tearDownAll(() async {
      if (!supabaseAvailable) return;
      await SuperAdminDataFactory.cleanup(testOrgRaceCondition);
      await SuperAdminDataFactory.cleanup(testOrgNetworkError);
      await SuperAdminDataFactory.cleanup(testOrgDoubleClick);
      await SuperAdminDataFactory.cleanup(testOrgNavigation);
      await SuperAdminDataFactory.cleanup(testOrgTokenExpiry);
      await SuperAdminDataFactory.cleanup(testOrgRevokeRace);
      await SuperAdminDataFactory.cleanup(testOrgCnpjDuplicate);
    });

    testWidgets('8.1 Consistência ao arquivar org durante edição concorrente '
        '(race condition)', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgRaceCondition.orgName,
      );

      // Iniciar o fluxo de arquivamento via UI
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

      // Simular edição concorrente via service_role (outro SuperAdmin
      // editando a org ao mesmo tempo)
      final client = SuperAdminTestConfig.createServiceRoleClient();
      try {
        await client
            .from('organizations')
            .update({'name': 'Adverse Race Condition Org (Editada)'})
            .eq('id', testOrgRaceCondition.orgId);
      } finally {
        await client.dispose();
      }

      // Preencher justificativa e confirmar o arquivamento
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Teste de race condition — arquivamento durante edição concorrente',
      );
      await SuperAdminWidgetHelpers.confirmModal(tester);

      // Aguardar processamento
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // Verificar consistência: o sistema deve ter completado a operação
      // sem corrupção de estado, OU exibido erro de conflito.
      final status = await SuperAdminDbVerifier.getOrgStatus(
        testOrgRaceCondition.orgId,
      );

      // O resultado aceitável é:
      // 1. Org foi arquivada com sucesso (status = ARCHIVED) — a edição
      //    concorrente não impediu o arquivamento
      // 2. Org permanece ACTIVE com mensagem de erro de conflito
      if (status == 'ARCHIVED') {
        // Verificar que a cascata foi executada corretamente
        await SuperAdminDbVerifier.assertAllUsersActiveStatus(
          orgId: testOrgRaceCondition.orgId,
          expectedActive: false,
        );
      } else {
        // Se não arquivou, deve ter exibido erro de conflito na UI
        expect(
          status,
          equals('ACTIVE'),
          reason:
              'Se o arquivamento falhou por conflito, o status deve '
              'permanecer ACTIVE (sem corrupção parcial) (Req 8.1)',
        );
      }

      // Verificar que não houve corrupção de dados (CNPJ inalterado)
      await SuperAdminDbVerifier.assertIdentityImmutable(
        orgId: testOrgRaceCondition.orgId,
        expectedCnpj: testOrgRaceCondition.cnpj,
      );
    });

    testWidgets('8.2 Exibição de erro e retry ao interromper rede durante '
        'arquivamento', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // Verificar estado inicial
      final statusBefore = await SuperAdminDbVerifier.getOrgStatus(
        testOrgNetworkError.orgId,
      );
      expect(statusBefore, equals('ACTIVE'));

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgNetworkError.orgName,
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

      // Preencher justificativa
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Teste de erro de rede — cenário adverso com retry',
      );

      // Simular falha de rede ANTES de confirmar
      final originalOverrides = HttpOverrides.current;
      HttpOverrides.global = _FailingHttpOverrides();

      try {
        // Confirmar (a operação deve falhar por rede)
        await SuperAdminWidgetHelpers.confirmModal(tester);

        // Aguardar feedback de erro
        await SuperAdminWidgetHelpers.waitForSnackbar(tester, 'Erro');

        // Verificar que a aplicação não crashou
        expect(
          tester.takeException(),
          isNull,
          reason:
              'A aplicação não deve crashar em caso de falha de rede '
              '(Req 8.2)',
        );
      } finally {
        // Restaurar HttpOverrides original para permitir retry
        HttpOverrides.global = originalOverrides;
      }

      // Verificar que o estado no DB não mudou (atomicidade)
      final statusAfterError = await SuperAdminDbVerifier.getOrgStatus(
        testOrgNetworkError.orgId,
      );
      expect(
        statusAfterError,
        equals('ACTIVE'),
        reason:
            'organization.status deve permanecer ACTIVE após erro de '
            'rede (Req 8.2)',
      );

      // Verificar que a UI permite retry: o botão de arquivar ou o
      // modal ainda deve estar acessível para nova tentativa.
      // Tentar a operação novamente (com rede restaurada)
      final retryArchiveButton = find.byTooltip('Arquivar');
      final retryArchiveText = find.widgetWithText(FilledButton, 'Arquivar');
      final retryArchiveElevated = find.widgetWithText(
        ElevatedButton,
        'Arquivar',
      );
      final retryButton = find.textContaining('Tentar novamente');

      final canRetry =
          retryArchiveButton.evaluate().isNotEmpty ||
          retryArchiveText.evaluate().isNotEmpty ||
          retryArchiveElevated.evaluate().isNotEmpty ||
          retryButton.evaluate().isNotEmpty;

      expect(
        canRetry,
        isTrue,
        reason:
            'A UI deve permitir retry após erro de rede — o botão '
            '"Arquivar" ou "Tentar novamente" deve estar acessível '
            '(Req 8.2)',
      );
    });

    testWidgets('8.3 Idempotência de double-click em desativação de admin '
        '(apenas 1 operação processada)', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgDoubleClick.orgName,
      );
      await SuperAdminNavigationHelper.goToUsersTab(tester);

      // Obter o admin ativo para verificação
      final activeAdmin = testOrgDoubleClick.admins.firstWhere(
        (a) => a.isActive && !a.isPending,
      );

      // Verificar estado inicial
      final client = SuperAdminTestConfig.createServiceRoleClient();
      try {
        final rows = await client
            .from('user_roles')
            .select('is_active')
            .eq('user_id', activeAdmin.userId)
            .eq('organization_id', testOrgDoubleClick.orgId);
        expect(rows.first['is_active'], isTrue);
      } finally {
        await client.dispose();
      }

      // Localizar o botão de desativar
      final deactivateButton = find.byTooltip('Inativar Usuário');
      expect(
        deactivateButton,
        findsAtLeast(1),
        reason: 'O botão "Inativar Usuário" deve estar visível (Req 8.3)',
      );

      // Simular double-click rápido (dois taps em rápida sucessão)
      await tester.tap(deactivateButton.first);
      await tester.tap(deactivateButton.first);
      await tester.pumpAndSettle();

      // Se o modal foi exibido, confirmar a operação
      final dialog = find.byType(AlertDialog);
      final simpleDialog = find.byType(Dialog);
      if (dialog.evaluate().isNotEmpty || simpleDialog.evaluate().isNotEmpty) {
        await SuperAdminWidgetHelpers.confirmModal(tester);
      }

      // Aguardar processamento
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // Verificar no banco que apenas 1 operação foi processada:
      // Contar registros de audit log para esta operação
      final verifyClient = SuperAdminTestConfig.createServiceRoleClient();
      try {
        final auditLogs = await verifyClient
            .from('system_audit_log')
            .select()
            .eq('organization_id', testOrgDoubleClick.orgId)
            .eq('event_type', 'DEACTIVATE_USER');

        // Deve haver no máximo 1 registro de desativação para este admin
        final logsForAdmin = auditLogs.where((log) {
          final metadata = log['metadata'];
          if (metadata is Map && metadata.containsKey('user_id')) {
            return metadata['user_id'] == activeAdmin.userId;
          }
          return true; // Se não tem metadata específica, contar
        }).toList();

        expect(
          logsForAdmin.length,
          lessThanOrEqualTo(1),
          reason:
              'Apenas 1 operação de desativação deve ser processada '
              'mesmo com double-click (idempotência — Req 8.3). '
              'Encontrados: ${logsForAdmin.length} registros',
        );

        // Verificar que o admin está desativado (operação processada 1x)
        final userRows = await verifyClient
            .from('user_roles')
            .select('is_active')
            .eq('user_id', activeAdmin.userId)
            .eq('organization_id', testOrgDoubleClick.orgId);

        expect(
          userRows.first['is_active'],
          isFalse,
          reason: 'O admin deve estar desativado após a operação (Req 8.3)',
        );
      } finally {
        await verifyClient.dispose();
      }
    });

    testWidgets('8.4 Navegação para fora durante operação em andamento '
        '(complete ou cancel limpo)', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // Capturar estado antes da operação
      final statusBefore = await SuperAdminDbVerifier.getOrgStatus(
        testOrgNavigation.orgId,
      );
      expect(statusBefore, equals('ACTIVE'));

      final activeCountBefore = await SuperAdminDbVerifier.countActiveUsers(
        testOrgNavigation.orgId,
      );

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgNavigation.orgName,
      );

      // Iniciar operação de arquivamento (abrir modal)
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

      // Preencher justificativa (operação em andamento)
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Teste de navegação durante operação em andamento',
      );

      // Navegar para fora ANTES de confirmar (simula usuário saindo)
      await SuperAdminNavigationHelper.goToTenantList(tester);

      // Aguardar que a navegação complete
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // Verificar que o modal foi fechado (não está mais visível)
      final dialog = find.byType(AlertDialog);
      final simpleDialog = find.byType(Dialog);
      expect(
        dialog.evaluate().isEmpty && simpleDialog.evaluate().isEmpty,
        isTrue,
        reason: 'O modal deve ser fechado ao navegar para fora (Req 8.4)',
      );

      // Verificar que o estado no DB não foi alterado (operação cancelada)
      final statusAfter = await SuperAdminDbVerifier.getOrgStatus(
        testOrgNavigation.orgId,
      );
      expect(
        statusAfter,
        equals('ACTIVE'),
        reason:
            'organization.status deve permanecer ACTIVE quando o '
            'usuário navega para fora durante operação (Req 8.4)',
      );

      final activeCountAfter = await SuperAdminDbVerifier.countActiveUsers(
        testOrgNavigation.orgId,
      );
      expect(
        activeCountAfter,
        equals(activeCountBefore),
        reason:
            'O número de admins ativos não deve mudar quando o '
            'usuário navega para fora durante operação (Req 8.4)',
      );

      // Verificar que a aplicação está em estado limpo (sem erros)
      expect(
        tester.takeException(),
        isNull,
        reason:
            'A aplicação não deve ter exceções pendentes após '
            'navegação durante operação (Req 8.4)',
      );
    });

    testWidgets('8.5 Redirecionamento para login ao expirar token — dados '
        'sensíveis limpos ANTES do redirect (anti Flash de Dados)', (
      tester,
    ) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgTokenExpiry.orgName,
      );

      // Verificar que dados sensíveis estão visíveis antes da expiração
      final orgNameVisible = find.textContaining(testOrgTokenExpiry.orgName);
      expect(
        orgNameVisible,
        findsAtLeast(1),
        reason: 'O nome da org deve estar visível antes da expiração do token',
      );

      // Forçar expiração do token
      await SuperAdminAuthHelper.forceTokenExpiry();

      // Pump para processar o evento de auth state change
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // ANTES de verificar redirecionamento, garantir que dados
      // sensíveis foram limpos da tela (anti "Flash de Dados")
      await SuperAdminAuthHelper.assertNoSensitiveDataVisible(tester);

      // Verificar redirecionamento para tela de login
      // A tela de login deve conter campos de email e senha
      final loginFields = find.byType(TextFormField);
      final loginButton = find.widgetWithText(ElevatedButton, 'Entrar');
      final loginButtonFilled = find.widgetWithText(FilledButton, 'Entrar');

      final isOnLoginScreen =
          loginFields.evaluate().isNotEmpty &&
          (loginButton.evaluate().isNotEmpty ||
              loginButtonFilled.evaluate().isNotEmpty);

      expect(
        isOnLoginScreen,
        isTrue,
        reason:
            'O sistema deve redirecionar para a tela de login após '
            'expiração do token (Req 8.5)',
      );
    });

    testWidgets('8.6 Mensagem apropriada ao revogar convite já aceito '
        '(race condition)', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // Obter o admin pendente da org
      final pendingAdmin = testOrgRevokeRace.admins.firstWhere(
        (a) => a.isPending,
      );

      // Simular aceitação do convite via service_role (outro caminho)
      // ANTES do SuperAdmin tentar revogar via UI
      final client = SuperAdminTestConfig.createServiceRoleClient();
      try {
        // Marcar o convite como aceito
        await client
            .from('invitations')
            .update({
              'accepted_at_utc': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('organization_id', testOrgRevokeRace.orgId)
            .eq('email', pendingAdmin.email);

        // Ativar o admin (simula aceitação completa)
        await client
            .from('user_roles')
            .update({'is_active': true})
            .eq('user_id', pendingAdmin.userId)
            .eq('organization_id', testOrgRevokeRace.orgId);
      } finally {
        await client.dispose();
      }

      // Agora o SuperAdmin tenta revogar via UI (convite já aceito)
      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        testOrgRevokeRace.orgName,
      );
      await SuperAdminNavigationHelper.goToUsersTab(tester);

      // Tentar localizar o botão de revogar convite
      final revokeButton = find.byTooltip('Revogar Convite');

      if (revokeButton.evaluate().isNotEmpty) {
        // Se o botão ainda está visível (UI não atualizou), tentar revogar
        await tester.tap(revokeButton.first);
        await tester.pumpAndSettle();

        // Se um modal foi exibido, confirmar
        final dialog = find.byType(AlertDialog);
        final simpleDialog = find.byType(Dialog);
        if (dialog.evaluate().isNotEmpty ||
            simpleDialog.evaluate().isNotEmpty) {
          await SuperAdminWidgetHelpers.confirmModal(tester);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            SuperAdminTestConfig.defaultTimeout,
          );
        }

        // O sistema deve exibir mensagem apropriada (erro ou aviso)
        // indicando que o convite já foi aceito
        final errorMessage = find.textContaining('já aceito');
        final conflictMessage = find.textContaining('conflito');
        final warningMessage = find.textContaining('não é possível');
        final snackBar = find.byType(SnackBar);

        final hasAppropriateMessage =
            errorMessage.evaluate().isNotEmpty ||
            conflictMessage.evaluate().isNotEmpty ||
            warningMessage.evaluate().isNotEmpty ||
            snackBar.evaluate().isNotEmpty;

        expect(
          hasAppropriateMessage,
          isTrue,
          reason:
              'O sistema deve exibir mensagem apropriada ao tentar '
              'revogar convite já aceito (race condition — Req 8.6)',
        );

        // Verificar que a aplicação não crashou
        expect(
          tester.takeException(),
          isNull,
          reason:
              'A aplicação não deve crashar ao tentar revogar convite '
              'já aceito (Req 8.6)',
        );
      } else {
        // Se o botão de revogar não está visível, a UI já refletiu
        // que o convite foi aceito — comportamento correto.
        // O admin deve aparecer como ativo na lista.
        final adminEmail = find.textContaining(pendingAdmin.email);
        expect(
          adminEmail,
          findsAtLeast(1),
          reason:
              'O admin cujo convite foi aceito deve aparecer na lista '
              'como ativo (Req 8.6)',
        );
      }
    });

    testWidgets('9.6 Erro de CNPJ duplicado: rejeição ao criar org com CNPJ '
        'já existente', (tester) async {
      if (!supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // Confirmar que o CNPJ da org de teste existe no banco
      final cnpjExists = await SuperAdminDataFactory.cnpjExistsInDb(
        testOrgCnpjDuplicate.cnpj,
      );
      expect(
        cnpjExists,
        isTrue,
        reason:
            'O CNPJ de referência deve existir no banco antes do teste '
            'de duplicidade (Req 9.6)',
      );

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
      await SuperAdminNavigationHelper.goToTenantList(tester);

      // Localizar o botão de criar nova organização
      final createOrgButton = find.byTooltip('Nova Organização');
      final createOrgText = find.widgetWithText(
        FilledButton,
        'Nova Organização',
      );
      final createOrgElevated = find.widgetWithText(
        ElevatedButton,
        'Nova Organização',
      );
      final createOrgIcon = find.byIcon(Icons.add);

      Finder createButtonFinder;
      if (createOrgButton.evaluate().isNotEmpty) {
        createButtonFinder = createOrgButton;
      } else if (createOrgText.evaluate().isNotEmpty) {
        createButtonFinder = createOrgText;
      } else if (createOrgElevated.evaluate().isNotEmpty) {
        createButtonFinder = createOrgElevated;
      } else if (createOrgIcon.evaluate().isNotEmpty) {
        createButtonFinder = createOrgIcon;
      } else {
        createButtonFinder = find.textContaining('Nova');
      }

      expect(
        createButtonFinder,
        findsAtLeast(1),
        reason:
            'O botão de criar nova organização deve estar visível '
            '(Req 9.6)',
      );

      await tester.tap(createButtonFinder.first);
      await tester.pumpAndSettle();

      // Preencher o formulário de criação com o CNPJ duplicado
      final textFields = find.byType(TextFormField);
      expect(
        textFields,
        findsAtLeast(2),
        reason:
            'O formulário de criação deve ter pelo menos 2 campos '
            '(nome + CNPJ)',
      );

      // Preencher nome da organização.
      // Buscar campo por label text visível na UI.
      final nameLabel = find.text('Nome');
      final razaoLabel = find.text('Razão Social');

      Finder? nameFieldFinder;
      if (nameLabel.evaluate().isNotEmpty) {
        // Encontrar o TextFormField que é irmão/descendente do label
        final nameFieldByLabel = find.ancestor(
          of: nameLabel,
          matching: find.byType(TextFormField),
        );
        if (nameFieldByLabel.evaluate().isNotEmpty) {
          nameFieldFinder = nameFieldByLabel;
        }
      } else if (razaoLabel.evaluate().isNotEmpty) {
        final razaoFieldByLabel = find.ancestor(
          of: razaoLabel,
          matching: find.byType(TextFormField),
        );
        if (razaoFieldByLabel.evaluate().isNotEmpty) {
          nameFieldFinder = razaoFieldByLabel;
        }
      }

      if (nameFieldFinder != null && nameFieldFinder.evaluate().isNotEmpty) {
        await tester.enterText(
          nameFieldFinder.first,
          'Org Duplicada CNPJ Teste',
        );
      } else {
        // Fallback: usar o primeiro campo
        await tester.enterText(textFields.first, 'Org Duplicada CNPJ Teste');
      }
      await tester.pump();

      // Preencher CNPJ duplicado.
      // Buscar campo por label text "CNPJ" visível na UI.
      final cnpjLabel = find.text('CNPJ');

      Finder? cnpjFieldFinder;
      if (cnpjLabel.evaluate().isNotEmpty) {
        final cnpjFieldByLabel = find.ancestor(
          of: cnpjLabel,
          matching: find.byType(TextFormField),
        );
        if (cnpjFieldByLabel.evaluate().isNotEmpty) {
          cnpjFieldFinder = cnpjFieldByLabel;
        }
      }

      if (cnpjFieldFinder != null && cnpjFieldFinder.evaluate().isNotEmpty) {
        await tester.enterText(
          cnpjFieldFinder.first,
          testOrgCnpjDuplicate.cnpj,
        );
      } else {
        // Fallback: usar o segundo campo
        await tester.enterText(textFields.at(1), testOrgCnpjDuplicate.cnpj);
      }
      await tester.pump();

      // Tentar submeter o formulário
      final submitButton = find.widgetWithText(FilledButton, 'Criar');
      final submitElevated = find.widgetWithText(ElevatedButton, 'Criar');
      final submitSalvar = find.widgetWithText(FilledButton, 'Salvar');
      final submitSalvarElevated = find.widgetWithText(
        ElevatedButton,
        'Salvar',
      );
      final submitConfirmar = find.widgetWithText(FilledButton, 'Confirmar');

      Finder submitFinder;
      if (submitButton.evaluate().isNotEmpty) {
        submitFinder = submitButton;
      } else if (submitElevated.evaluate().isNotEmpty) {
        submitFinder = submitElevated;
      } else if (submitSalvar.evaluate().isNotEmpty) {
        submitFinder = submitSalvar;
      } else if (submitSalvarElevated.evaluate().isNotEmpty) {
        submitFinder = submitSalvarElevated;
      } else if (submitConfirmar.evaluate().isNotEmpty) {
        submitFinder = submitConfirmar;
      } else {
        submitFinder = find.textContaining('Criar');
      }

      expect(
        submitFinder,
        findsAtLeast(1),
        reason: 'O botão de submissão deve estar visível (Req 9.6)',
      );

      await tester.tap(submitFinder.first);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // Verificar que o sistema rejeitou a operação com mensagem de erro
      final duplicateError = find.textContaining('CNPJ');
      final duplicateErrorAlt = find.textContaining('duplicado');
      final duplicateErrorExists = find.textContaining('já existe');
      final duplicateErrorCadastrado = find.textContaining('já cadastrado');
      final errorSnackbar = find.byType(SnackBar);
      // Check for inline error text (typically rendered below the field)
      final errorInField = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.style?.color == Colors.red &&
            widget.data != null &&
            widget.data!.isNotEmpty,
      );

      final hasRejectionMessage =
          duplicateError.evaluate().isNotEmpty ||
          duplicateErrorAlt.evaluate().isNotEmpty ||
          duplicateErrorExists.evaluate().isNotEmpty ||
          duplicateErrorCadastrado.evaluate().isNotEmpty ||
          errorSnackbar.evaluate().isNotEmpty ||
          errorInField.evaluate().isNotEmpty;

      expect(
        hasRejectionMessage,
        isTrue,
        reason:
            'O sistema deve rejeitar a criação de org com CNPJ '
            'duplicado e exibir mensagem de erro apropriada (Req 9.6)',
      );

      // Verificar que a org duplicada NÃO foi criada no banco
      final verifyClient = SuperAdminTestConfig.createServiceRoleClient();
      try {
        final orgsWithCnpj = await verifyClient
            .from('organizations')
            .select('id, name')
            .eq('cnpj', testOrgCnpjDuplicate.cnpj);

        // Deve haver apenas 1 org com este CNPJ (a original)
        expect(
          orgsWithCnpj.length,
          equals(1),
          reason:
              'Deve existir apenas 1 organização com o CNPJ '
              '${testOrgCnpjDuplicate.cnpj} no banco (Req 9.6)',
        );

        expect(
          orgsWithCnpj.first['id'],
          equals(testOrgCnpjDuplicate.orgId),
          reason: 'A única org com este CNPJ deve ser a original (Req 9.6)',
        );
      } finally {
        await verifyClient.dispose();
      }
    });
  });
}

/// HttpOverrides que simula falha de rede para todos os requests.
///
/// Usado pelo teste 8.2 para verificar exibição de erro e capacidade
/// de retry quando a operação de arquivamento falha por erro de rede.
class _FailingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _FailingHttpClient();
  }
}

/// HttpClient que rejeita todas as conexões simulando falha de rede.
class _FailingHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout = const Duration(seconds: 1);

  @override
  Duration idleTimeout = const Duration(seconds: 1);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {}

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {}

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) {}

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) {}

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) {}

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) {}

  @override
  set findProxy(String Function(Uri url)? f) {}

  @override
  set keyLog(Function(String line)? callback) {}

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _fail();

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => _fail();

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> head(String host, int port, String path) => _fail();

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _fail();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _fail();

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _fail();

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> post(String host, int port, String path) => _fail();

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _fail();

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _fail();

  Future<HttpClientRequest> _fail() {
    return Future.error(
      const SocketException(
        'Simulated network failure (adverse_scenarios test)',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
