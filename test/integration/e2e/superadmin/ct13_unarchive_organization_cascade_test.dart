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

/// Testes E2E para o cenário CT13: Desarquivamento de Organização com Cascata.
///
/// Valida os fluxos de desarquivamento de organizações pelo SuperAdmin,
/// incluindo Modal_Confirmação com justificativa, Cascata_Desbloqueio de
/// todos os admins, alternância instantânea do botão no cabeçalho,
/// restauração de botões de ação e impedimento de duplicidade.
///
/// **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7**

// ── File-level shared state ───────────────────────────────────────────────────

late TestOrgData _testOrg;
late TestOrgData _testOrgDuplicate;
bool _supabaseAvailable = false;

// ── Test cases ────────────────────────────────────────────────────────────────

void _test51() {
  testWidgets(
    '5.1 Modal_Confirmação com campo de justificativa ao clicar Desarquivar',
    (tester) async {
      if (!_supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);

      // Filtrar por organizações arquivadas/suspensas
      await SuperAdminNavigationHelper.goToTenantList(tester);
      await SuperAdminNavigationHelper.filterArchived(tester);

      // Navegar até o detalhe da org arquivada
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        _testOrg.orgName,
      );

      // Localizar o botão "Desarquivar" no cabeçalho de detalhes da org
      final buttonFinder = _findUnarchiveButton(tester);

      expect(
        buttonFinder,
        findsAtLeast(1),
        reason:
            'O botão "Desarquivar" deve estar visível no cabeçalho da org '
            'arquivada (Req 5.1)',
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
            '"Desarquivar" (Req 5.1)',
      );

      // Verificar que o modal contém um campo de justificativa (TextField)
      // ReasonConfirmationDialog uses bare TextField, not TextFormField.
      final justificationField = find.byType(TextField);
      expect(
        justificationField,
        findsAtLeast(1),
        reason:
            'O modal deve conter um campo de justificativa '
            '(TextField) (Req 5.1)',
      );

      // Cancelar para não alterar estado para próximos testes
      await SuperAdminWidgetHelpers.cancelModal(tester);
    },
  );
}

void _test52() {
  testWidgets('5.2 Status muda para ACTIVE no DB após confirmação', (
    tester,
  ) async {
    if (!_supabaseAvailable) {
      markTestSkipped('Supabase local não disponível.');
      return;
    }

    // Verificar estado inicial (ARCHIVED)
    final statusBefore = await SuperAdminDbVerifier.getOrgStatus(
      _testOrg.orgId,
    );
    expect(
      statusBefore,
      equals('ARCHIVED'),
      reason: 'Org deve estar ARCHIVED antes do desarquivamento',
    );

    await SuperAdminAuthHelper.loginAsSuperAdmin(tester);

    // Filtrar por organizações arquivadas/suspensas
    await SuperAdminNavigationHelper.goToTenantList(tester);
    await SuperAdminNavigationHelper.filterArchived(tester);

    // Navegar até o detalhe da org arquivada
    await SuperAdminNavigationHelper.goToTenantDetail(tester, _testOrg.orgName);

    // Clicar em "Desarquivar"
    final buttonFinder = _findUnarchiveButton(tester);
    expect(buttonFinder, findsAtLeast(1));
    await tester.tap(buttonFinder.first);
    await tester.pumpAndSettle();

    // Preencher justificativa e confirmar
    await SuperAdminWidgetHelpers.fillJustification(
      tester,
      'Desarquivamento para teste E2E CT13 — validação de cascata',
    );
    await SuperAdminWidgetHelpers.confirmModal(tester);

    // Aguardar processamento
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );

    // Verificar no banco que o status mudou para ACTIVE
    final statusAfter = await SuperAdminDbVerifier.getOrgStatus(_testOrg.orgId);
    expect(
      statusAfter,
      equals('ACTIVE'),
      reason:
          'organization.status deve ser ACTIVE após confirmação '
          'do desarquivamento (Req 5.2)',
    );
  });
}

void _test53() {
  testWidgets('5.3 Cascata_Desbloqueio: todos admins com is_active=true e '
      'banned_until=null', (tester) async {
    if (!_supabaseAvailable) {
      markTestSkipped('Supabase local não disponível.');
      return;
    }

    // Guard: CT13.5.2 must have run and succeeded (org must be ACTIVE).
    final precondStatus = await SuperAdminDbVerifier.getOrgStatus(
      _testOrg.orgId,
    );
    if (precondStatus != 'ACTIVE') {
      markTestSkipped(
        'CT13.5.3 skipped: org is $precondStatus — CT13.5.2 must pass first.',
      );
      return;
    }

    // A org já foi desarquivada no teste 5.2.
    // Verificar que TODOS os admins estão desbloqueados.

    // Verificar is_active=true para todos
    await SuperAdminDbVerifier.assertAllUsersActiveStatus(
      orgId: _testOrg.orgId,
      expectedActive: true,
    );

    // Verificar banned_until=null para todos
    await SuperAdminDbVerifier.assertAllUsersBannedStatus(
      orgId: _testOrg.orgId,
      shouldBeBanned: false,
    );

    // Verificar contagem: todos os 3 admins devem estar ativos
    final activeCount = await SuperAdminDbVerifier.countActiveUsers(
      _testOrg.orgId,
    );
    expect(
      activeCount,
      equals(_testOrg.admins.length),
      reason:
          'O número de admins ativos deve ser igual ao total de '
          'admins da org (${_testOrg.admins.length}) após '
          'desarquivamento (Req 5.3)',
    );
  });
}

void _test54() {
  testWidgets(
    '5.4 Alternância instantânea do botão no cabeçalho (sem refresh)',
    (tester) async {
      if (!_supabaseAvailable) {
        markTestSkipped('Supabase local não disponível.');
        return;
      }

      // Re-arquivar a org para testar a alternância de botão
      await _archiveOrgInDb(_testOrg);

      await SuperAdminAuthHelper.loginAsSuperAdmin(tester);

      // Filtrar por organizações arquivadas/suspensas
      await SuperAdminNavigationHelper.goToTenantList(tester);
      await SuperAdminNavigationHelper.filterArchived(tester);

      // Navegar até o detalhe da org arquivada
      await SuperAdminNavigationHelper.goToTenantDetail(
        tester,
        _testOrg.orgName,
      );

      // Verificar que "Desarquivar" está presente ANTES da operação
      final desarquivarBefore = _findUnarchiveButton(tester);
      expect(
        desarquivarBefore,
        findsAtLeast(1),
        reason: 'O botão "Desarquivar" deve estar visível antes da operação',
      );

      // Verificar que "Arquivar" NÃO está presente em org arquivada
      final arquivarBefore = find.widgetWithText(FilledButton, 'Arquivar');
      final arquivarBeforeElevated = find.widgetWithText(
        ElevatedButton,
        'Arquivar',
      );
      expect(
        arquivarBefore.evaluate().isEmpty &&
            arquivarBeforeElevated.evaluate().isEmpty,
        isTrue,
        reason: 'O botão "Arquivar" não deve estar visível em org arquivada',
      );

      // Clicar em "Desarquivar"
      await tester.tap(desarquivarBefore.first);
      await tester.pumpAndSettle();

      // Preencher justificativa e confirmar
      await SuperAdminWidgetHelpers.fillJustification(
        tester,
        'Teste de alternância de botão CT13 — sem refresh',
      );
      await SuperAdminWidgetHelpers.confirmModal(tester);

      // Aguardar processamento (sem refresh manual da página)
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        SuperAdminTestConfig.defaultTimeout,
      );

      // Verificar que o botão alternou INSTANTANEAMENTE para "Arquivar"
      // (sem necessidade de refresh da página)
      final arquivarAfter = find.byTooltip('Arquivar');
      final arquivarAfterText = find.widgetWithText(FilledButton, 'Arquivar');
      final arquivarAfterElevated = find.widgetWithText(
        ElevatedButton,
        'Arquivar',
      );
      final arquivarAfterGeneric = find.textContaining('Arquivar');

      final archiveButtonPresent =
          arquivarAfter.evaluate().isNotEmpty ||
          arquivarAfterText.evaluate().isNotEmpty ||
          arquivarAfterElevated.evaluate().isNotEmpty ||
          arquivarAfterGeneric.evaluate().isNotEmpty;

      expect(
        archiveButtonPresent,
        isTrue,
        reason:
            'O botão deve alternar instantaneamente para "Arquivar" '
            'após desarquivamento, sem necessidade de refresh (Req 5.4)',
      );

      // Verificar que "Desarquivar" NÃO está mais presente
      final desarquivarAfter = find.widgetWithText(FilledButton, 'Desarquivar');
      final desarquivarAfterElevated = find.widgetWithText(
        ElevatedButton,
        'Desarquivar',
      );
      expect(
        desarquivarAfter.evaluate().isEmpty &&
            desarquivarAfterElevated.evaluate().isEmpty,
        isTrue,
        reason:
            'O botão "Desarquivar" não deve estar visível após '
            'desarquivamento bem-sucedido (Req 5.4)',
      );
    },
  );
}

void _test55() {
  testWidgets('5.5 Botões de ação restaurados após desarquivamento', (
    tester,
  ) async {
    if (!_supabaseAvailable) {
      markTestSkipped('Supabase local não disponível.');
      return;
    }

    // Guard: CT13.5.4 must have run and succeeded (org must be ACTIVE).
    final precondStatus = await SuperAdminDbVerifier.getOrgStatus(
      _testOrg.orgId,
    );
    if (precondStatus != 'ACTIVE') {
      markTestSkipped(
        'CT13.5.5 skipped: org is $precondStatus — CT13.5.4 must pass first.',
      );
      return;
    }

    // A org foi desarquivada no teste 5.4.
    // Verificar que os botões de ação estão restaurados.
    await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
    await SuperAdminNavigationHelper.goToTenantList(tester);
    await SuperAdminNavigationHelper.goToTenantDetail(tester, _testOrg.orgName);
    await SuperAdminNavigationHelper.goToUsersTab(tester);

    // Verificar presença do botão "Adicionar Administrador" (ou equivalente)
    final addAdminButton = find.byTooltip('Adicionar Administrador');
    final addAdminText = find.widgetWithText(FilledButton, 'Adicionar');
    final addAdminElevated = find.widgetWithText(ElevatedButton, 'Adicionar');
    final addAdminIcon = find.byTooltip('Adicionar');

    final addAdminPresent =
        addAdminButton.evaluate().isNotEmpty ||
        addAdminText.evaluate().isNotEmpty ||
        addAdminElevated.evaluate().isNotEmpty ||
        addAdminIcon.evaluate().isNotEmpty;

    expect(
      addAdminPresent,
      isTrue,
      reason:
          'O botão "Adicionar Administrador" deve estar visível após '
          'desarquivamento da org (Req 5.5)',
    );

    // Verificar presença do botão "Arquivar" no cabeçalho
    // (indica que a org está ativa e pode ser arquivada novamente)
    final archiveButton = find.byTooltip('Arquivar');
    final archiveButtonText = find.widgetWithText(FilledButton, 'Arquivar');
    final archiveButtonElevated = find.widgetWithText(
      ElevatedButton,
      'Arquivar',
    );
    final archiveGeneric = find.textContaining('Arquivar');

    final archivePresent =
        archiveButton.evaluate().isNotEmpty ||
        archiveButtonText.evaluate().isNotEmpty ||
        archiveButtonElevated.evaluate().isNotEmpty ||
        archiveGeneric.evaluate().isNotEmpty;

    expect(
      archivePresent,
      isTrue,
      reason:
          'O botão "Arquivar" deve estar visível no cabeçalho após '
          'desarquivamento (Req 5.5)',
    );
  });
}

void _test56() {
  testWidgets('5.6 Botão de confirmação desabilitado com justificativa vazia', (
    tester,
  ) async {
    if (!_supabaseAvailable) {
      markTestSkipped('Supabase local não disponível.');
      return;
    }

    // Re-arquivar a org para poder abrir o modal de desarquivamento
    await _archiveOrgInDb(_testOrg);

    await SuperAdminAuthHelper.loginAsSuperAdmin(tester);

    // Filtrar por organizações arquivadas/suspensas
    await SuperAdminNavigationHelper.goToTenantList(tester);
    await SuperAdminNavigationHelper.filterArchived(tester);

    // Navegar até o detalhe da org arquivada
    await SuperAdminNavigationHelper.goToTenantDetail(tester, _testOrg.orgName);

    // Clicar em "Desarquivar"
    final buttonFinder = _findUnarchiveButton(tester);
    expect(buttonFinder, findsAtLeast(1));
    await tester.tap(buttonFinder.first);
    await tester.pumpAndSettle();

    // Verificar que o botão de confirmação está desabilitado
    // (justificativa vazia)
    final isEnabled = SuperAdminWidgetHelpers.isConfirmButtonEnabled(tester);
    expect(
      isEnabled,
      isFalse,
      reason:
          'O botão de confirmação deve estar desabilitado quando a '
          'justificativa está vazia no modal de desarquivamento (Req 5.6)',
    );

    // Cancelar o modal
    await SuperAdminWidgetHelpers.cancelModal(tester);
  });
}

void _test57() {
  testWidgets('5.7 Impedimento de desarquivamento de org já ativa', (
    tester,
  ) async {
    if (!_supabaseAvailable) {
      markTestSkipped('Supabase local não disponível.');
      return;
    }

    // A testOrgDuplicate está ACTIVE — tentar desarquivar deve ser impedido.
    final status = await SuperAdminDbVerifier.getOrgStatus(
      _testOrgDuplicate.orgId,
    );
    expect(
      status,
      equals('ACTIVE'),
      reason: 'Org de teste de duplicidade deve estar ACTIVE',
    );

    await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
    await SuperAdminNavigationHelper.goToTenantList(tester);
    await SuperAdminNavigationHelper.goToTenantDetail(
      tester,
      _testOrgDuplicate.orgName,
    );

    // Verificar que o botão "Desarquivar" NÃO está disponível
    // para uma org já ativa (deve ter "Arquivar" em seu lugar)
    final unarchiveButton = find.byTooltip('Desarquivar');
    final unarchiveButtonText = find.widgetWithText(
      FilledButton,
      'Desarquivar',
    );
    final unarchiveButtonElevated = find.widgetWithText(
      ElevatedButton,
      'Desarquivar',
    );

    final unarchivePresent =
        unarchiveButton.evaluate().isNotEmpty ||
        unarchiveButtonText.evaluate().isNotEmpty ||
        unarchiveButtonElevated.evaluate().isNotEmpty;

    if (unarchivePresent) {
      // Se o botão "Desarquivar" está presente em org ativa,
      // tentar clicar e verificar que o sistema impede a operação
      Finder duplicateButtonFinder;
      if (unarchiveButton.evaluate().isNotEmpty) {
        duplicateButtonFinder = unarchiveButton;
      } else if (unarchiveButtonText.evaluate().isNotEmpty) {
        duplicateButtonFinder = unarchiveButtonText;
      } else {
        duplicateButtonFinder = unarchiveButtonElevated;
      }

      await tester.tap(duplicateButtonFinder.first);
      await tester.pumpAndSettle();

      // O sistema deve exibir mensagem de erro ou impedir a operação
      final errorText = find.textContaining('já ativa');
      final errorSnackbar = find.byType(SnackBar);
      final blockDialog = find.byType(AlertDialog);

      expect(
        errorText.evaluate().isNotEmpty ||
            errorSnackbar.evaluate().isNotEmpty ||
            blockDialog.evaluate().isNotEmpty,
        isTrue,
        reason:
            'O sistema deve impedir desarquivamento de org já ativa '
            'com mensagem de erro ou bloqueio (Req 5.7)',
      );
    } else {
      // O botão "Desarquivar" não está presente — comportamento correto:
      // o sistema impede a operação por não oferecer o botão.
      // Verificar que "Arquivar" está presente em seu lugar.
      final archiveButton = find.byTooltip('Arquivar');
      final archiveText = find.textContaining('Arquivar');

      expect(
        archiveButton.evaluate().isNotEmpty ||
            archiveText.evaluate().isNotEmpty,
        isTrue,
        reason:
            'O botão "Arquivar" deve estar presente no lugar de '
            '"Desarquivar" para org já ativa (Req 5.7)',
      );
    }
  });
}

// ── Entry point ───────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CT13: Desarquivamento de Organização com Cascata', () {
    setUpAll(() async {
      _supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!_supabaseAvailable) return;

      // Criar org com 3 admins e arquivá-la programaticamente
      _testOrg = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT13 Org Desarquivar',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 3,
        pendingAdmins: 0,
      );

      // Arquivar a org diretamente no DB para simular estado inicial
      await _archiveOrgInDb(_testOrg);

      // Criar org separada para teste de desarquivamento duplicado
      // (esta org permanecerá ACTIVE para testar impedimento)
      _testOrgDuplicate = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT13 Org Duplicado',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 0,
      );
    });

    tearDownAll(() async {
      if (!_supabaseAvailable) return;
      await SuperAdminDataFactory.cleanup(_testOrg);
      await SuperAdminDataFactory.cleanup(_testOrgDuplicate);
    });

    _test51();
    _test52();
    _test53();
    _test54();
    _test55();
    _test56();
    _test57();
  });
}

// ── Helpers privados ──────────────────────────────────────────────────────────

/// Localiza o botão "Desarquivar" no cabeçalho da org.
///
/// Busca por tooltip, FilledButton, ElevatedButton ou texto genérico.
Finder _findUnarchiveButton(WidgetTester tester) {
  final byTooltip = find.byTooltip('Desarquivar');
  if (byTooltip.evaluate().isNotEmpty) return byTooltip;

  final byFilled = find.widgetWithText(FilledButton, 'Desarquivar');
  if (byFilled.evaluate().isNotEmpty) return byFilled;

  final byElevated = find.widgetWithText(ElevatedButton, 'Desarquivar');
  if (byElevated.evaluate().isNotEmpty) return byElevated;

  // Fallback: buscar por texto "Desarquivar" em qualquer widget
  return find.textContaining('Desarquivar');
}

/// Archives an org directly in the DB via the `test_archive_org_for_e2e` RPC.
///
/// Single SQL round-trip: sets organizations.status='ARCHIVED',
/// user_roles.is_active=false, and auth.users.banned_until to the GoTrue-safe
/// finite sentinel '9999-12-31 23:59:59+00'. Bypasses GoTrue Admin REST API —
/// which returns HTTP 500 when any auth.users row has banned_until='infinity'
/// (migration 20260519000002_test_helpers_e2e).
Future<void> _archiveOrgInDb(TestOrgData org) async {
  final client = SuperAdminTestConfig.createServiceRoleClient();
  try {
    await client.rpc<void>(
      'test_archive_org_for_e2e',
      params: {'p_org_id': org.orgId},
    );
  } finally {
    await client.dispose();
  }
}
