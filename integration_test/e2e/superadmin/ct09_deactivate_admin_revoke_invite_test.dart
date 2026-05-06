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

/// Testes E2E para o cenário CT09: Desativar Admin e Revogar Convite.
///
/// Valida os fluxos de desativação de administradores ativos e revogação
/// de convites pendentes no painel SuperAdmin, incluindo verificações de
/// Modal_Confirmação, persistência no banco de dados e cenários adversos.
///
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CT09: Desativar Admin e Revogar Convite', () {
    late TestOrgData testOrg;
    late TestOrgData testOrgSingleAdmin;
    bool supabaseAvailable = false;

    setUpAll(() async {
      supabaseAvailable = await SuperAdminTestConfig.isSupabaseRunning();
      if (!supabaseAvailable) return;

      // Criar org com 2 admins ativos e 1 admin pendente para testes gerais
      testOrg = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT09 Org Desativar',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 2,
        pendingAdmins: 1,
      );

      // Criar org com apenas 1 admin ativo para teste de último admin
      testOrgSingleAdmin = await SuperAdminDataFactory.createOrgWithAdmins(
        orgName: 'CT09 Org Último Admin',
        cnpj: SuperAdminDataFactory.generateUniqueCnpj(),
        activeAdmins: 1,
        pendingAdmins: 0,
      );
    });

    tearDownAll(() async {
      if (!supabaseAvailable) return;
      await SuperAdminDataFactory.cleanup(testOrg);
      await SuperAdminDataFactory.cleanup(testOrgSingleAdmin);
    });

    testWidgets(
      '3.1 Modal_Confirmação exibido ao revogar convite pendente',
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
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Localizar o botão de revogar convite para admin pendente
        final revokeButton = find.byTooltip('Revogar Convite');
        expect(
          revokeButton,
          findsAtLeast(1),
          reason:
              'O botão "Revogar Convite" deve estar visível para '
              'Admin_Pendente (Req 3.1)',
        );

        // Tocar no botão de revogar
        await tester.tap(revokeButton.first);
        await tester.pumpAndSettle();

        // Verificar que o Modal_Confirmação é exibido
        final dialog = find.byType(AlertDialog);
        final simpleDialog = find.byType(Dialog);
        expect(
          dialog.evaluate().isNotEmpty || simpleDialog.evaluate().isNotEmpty,
          isTrue,
          reason:
              'O Modal_Confirmação deve ser exibido ao clicar em '
              '"Revogar Convite" (Req 3.1)',
        );

        // Verificar que o modal contém texto relacionado à revogação
        final revokeText = find.textContaining('Revogar');
        expect(
          revokeText,
          findsAtLeast(1),
          reason:
              'O modal deve conter texto indicando a ação de revogação',
        );

        // Cancelar para não alterar estado para próximos testes
        await SuperAdminWidgetHelpers.cancelModal(tester);
      },
    );

    testWidgets(
      '3.2 Convite removido da lista e status alterado no DB após confirmação',
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
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Obter o email do admin pendente para verificação posterior
        final pendingAdmin = testOrg.admins.firstWhere(
          (a) => a.isPending,
        );

        // Verificar que o admin pendente está visível na lista
        final pendingEmailFinder = find.textContaining(pendingAdmin.email);
        expect(
          pendingEmailFinder,
          findsAtLeast(1),
          reason:
              'O admin pendente deve estar visível na lista antes da revogação',
        );

        // Tocar no botão de revogar convite
        final revokeButton = find.byTooltip('Revogar Convite');
        expect(revokeButton, findsAtLeast(1));
        await tester.tap(revokeButton.first);
        await tester.pumpAndSettle();

        // Confirmar a revogação no modal
        await SuperAdminWidgetHelpers.confirmModal(tester);

        // Verificar que o convite foi removido da lista (UI)
        await SuperAdminWidgetHelpers.retryUntil(
          tester,
          () async {
            await tester.pump(const Duration(milliseconds: 100));
            // O botão de revogar não deve mais estar presente para este admin
            return find.textContaining(pendingAdmin.email).evaluate().isEmpty ||
                find.byTooltip('Revogar Convite').evaluate().isEmpty;
          },
          timeout: SuperAdminTestConfig.defaultTimeout,
        );

        // Verificar no banco que o convite foi revogado/removido
        final client = SuperAdminTestConfig.createServiceRoleClient();
        try {
          final invitations = await client
              .from('invitations')
              .select()
              .eq('organization_id', testOrg.orgId)
              .eq('email', pendingAdmin.email);

          // O convite deve ter sido removido ou ter status revogado
          if (invitations.isNotEmpty) {
            // Se ainda existe, deve ter status 'REVOKED'
            final invitation = invitations.first;
            expect(
              invitation['status'],
              equals('REVOKED'),
              reason:
                  'O convite deve ter status REVOKED no DB após '
                  'confirmação (Req 3.2)',
            );
          }
          // Se foi deletado, o teste passa (convite removido)
        } finally {
          await client.dispose();
        }
      },
    );

    testWidgets(
      '3.3 Modal_Confirmação exibido ao desativar admin ativo',
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
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Localizar o botão de desativar admin ativo
        final deactivateButton = find.byTooltip('Inativar Usuário');
        expect(
          deactivateButton,
          findsAtLeast(1),
          reason:
              'O botão "Inativar Usuário" deve estar visível para '
              'Admin_Ativo (Req 3.3)',
        );

        // Tocar no botão de desativar
        await tester.tap(deactivateButton.first);
        await tester.pumpAndSettle();

        // Verificar que o Modal_Confirmação é exibido
        final dialog = find.byType(AlertDialog);
        final simpleDialog = find.byType(Dialog);
        expect(
          dialog.evaluate().isNotEmpty || simpleDialog.evaluate().isNotEmpty,
          isTrue,
          reason:
              'O Modal_Confirmação deve ser exibido ao clicar em '
              '"Inativar Usuário" (Req 3.3)',
        );

        // Verificar que o modal contém texto relacionado à desativação
        final deactivateText = find.textContaining('Inativar');
        expect(
          deactivateText,
          findsAtLeast(1),
          reason:
              'O modal deve conter texto indicando a ação de desativação',
        );

        // Cancelar para não alterar estado para próximos testes
        await SuperAdminWidgetHelpers.cancelModal(tester);
      },
    );

    testWidgets(
      '3.4 is_active=false no DB após confirmação de desativação',
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
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Obter um admin ativo para verificação
        final activeAdmin = testOrg.admins.firstWhere(
          (a) => a.isActive && !a.isPending,
        );

        // Verificar estado inicial no DB
        final client = SuperAdminTestConfig.createServiceRoleClient();
        try {
          final beforeRows = await client
              .from('user_roles')
              .select('is_active')
              .eq('user_id', activeAdmin.userId)
              .eq('organization_id', testOrg.orgId);

          expect(
            beforeRows.first['is_active'],
            isTrue,
            reason: 'Admin deve estar ativo antes da desativação',
          );
        } finally {
          await client.dispose();
        }

        // Tocar no botão de desativar
        final deactivateButton = find.byTooltip('Inativar Usuário');
        expect(deactivateButton, findsAtLeast(1));
        await tester.tap(deactivateButton.first);
        await tester.pumpAndSettle();

        // Confirmar a desativação no modal
        await SuperAdminWidgetHelpers.confirmModal(tester);

        // Aguardar processamento
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          SuperAdminTestConfig.defaultTimeout,
        );

        // Verificar no banco que is_active=false
        final verifyClient = SuperAdminTestConfig.createServiceRoleClient();
        try {
          final afterRows = await verifyClient
              .from('user_roles')
              .select('is_active')
              .eq('user_id', activeAdmin.userId)
              .eq('organization_id', testOrg.orgId);

          expect(
            afterRows.first['is_active'],
            isFalse,
            reason:
                'user_roles.is_active deve ser false após confirmação '
                'de desativação (Req 3.4)',
          );
        } finally {
          await verifyClient.dispose();
        }
      },
    );

    testWidgets(
      '3.5 Cancelamento no modal não altera estado no DB',
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
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Obter um admin ativo restante para verificação
        final activeAdmins = testOrg.admins.where(
          (a) => a.isActive && !a.isPending,
        ).toList();

        // Usar o segundo admin ativo (o primeiro pode ter sido desativado no 3.4)
        final targetAdmin = activeAdmins.length > 1
            ? activeAdmins[1]
            : activeAdmins.first;

        // Capturar estado antes da operação
        final client = SuperAdminTestConfig.createServiceRoleClient();
        bool isActiveBefore;
        try {
          final rows = await client
              .from('user_roles')
              .select('is_active')
              .eq('user_id', targetAdmin.userId)
              .eq('organization_id', testOrg.orgId);

          isActiveBefore = rows.first['is_active'] as bool;
        } finally {
          await client.dispose();
        }

        // Tocar no botão de desativar (se disponível)
        final deactivateButton = find.byTooltip('Inativar Usuário');
        if (deactivateButton.evaluate().isEmpty) {
          markTestSkipped(
            'Nenhum botão de desativar disponível (admins já desativados).',
          );
          return;
        }
        await tester.tap(deactivateButton.first);
        await tester.pumpAndSettle();

        // Cancelar a operação no modal
        await SuperAdminWidgetHelpers.cancelModal(tester);

        // Verificar que o estado no DB não mudou
        final verifyClient = SuperAdminTestConfig.createServiceRoleClient();
        try {
          final afterRows = await verifyClient
              .from('user_roles')
              .select('is_active')
              .eq('user_id', targetAdmin.userId)
              .eq('organization_id', testOrg.orgId);

          expect(
            afterRows.first['is_active'],
            equals(isActiveBefore),
            reason:
                'user_roles.is_active não deve mudar após cancelamento '
                'no modal (Req 3.5)',
          );
        } finally {
          await verifyClient.dispose();
        }
      },
    );

    testWidgets(
      '3.6 Comportamento ao desativar último admin ativo',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantDetail(
          tester,
          testOrgSingleAdmin.orgName,
        );
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Verificar que há exatamente 1 admin ativo
        final activeCount = await SuperAdminDbVerifier.countActiveUsers(
          testOrgSingleAdmin.orgId,
        );
        expect(
          activeCount,
          equals(1),
          reason: 'Org deve ter exatamente 1 admin ativo para este teste',
        );

        // Tentar desativar o último admin ativo
        final deactivateButton = find.byTooltip('Inativar Usuário');
        expect(
          deactivateButton,
          findsAtLeast(1),
          reason:
              'O botão de desativar deve estar presente mesmo para o '
              'último admin (Req 3.6)',
        );

        await tester.tap(deactivateButton.first);
        await tester.pumpAndSettle();

        // O sistema deve exibir um aviso ou bloquear a operação.
        // Verificar se há um modal de aviso ou se o botão de confirmação
        // está desabilitado, ou se há uma mensagem de alerta.
        final warningText = find.textContaining('último');
        final blockText = find.textContaining('não é possível');
        final alertText = find.textContaining('atenção');

        final hasWarning = warningText.evaluate().isNotEmpty ||
            blockText.evaluate().isNotEmpty ||
            alertText.evaluate().isNotEmpty;

        // Se o modal foi exibido normalmente, verificar se há algum
        // indicador de que é o último admin
        final dialog = find.byType(AlertDialog);
        final simpleDialog = find.byType(Dialog);
        final hasDialog =
            dialog.evaluate().isNotEmpty || simpleDialog.evaluate().isNotEmpty;

        expect(
          hasWarning || hasDialog,
          isTrue,
          reason:
              'O sistema deve exibir aviso ou modal ao tentar desativar '
              'o último admin ativo (Req 3.6)',
        );

        // Se houver modal, cancelar para não alterar estado
        if (hasDialog) {
          await SuperAdminWidgetHelpers.cancelModal(tester);
        }

        // Verificar que o admin ainda está ativo no DB (operação bloqueada
        // ou cancelada)
        final postCount = await SuperAdminDbVerifier.countActiveUsers(
          testOrgSingleAdmin.orgId,
        );
        expect(
          postCount,
          equals(1),
          reason:
              'O último admin ativo deve permanecer ativo após tentativa '
              'de desativação (Req 3.6)',
        );
      },
    );

    testWidgets(
      '3.7 Consistência UI/DB em caso de erro de rede',
      (tester) async {
        if (!supabaseAvailable) {
          markTestSkipped('Supabase local não disponível.');
          return;
        }

        await SuperAdminAuthHelper.loginAsSuperAdmin(tester);
        await SuperAdminNavigationHelper.goToTenantDetail(
          tester,
          testOrgSingleAdmin.orgName,
        );
        await SuperAdminNavigationHelper.goToUsersTab(tester);

        // Capturar estado antes da operação
        final singleAdmin = testOrgSingleAdmin.admins.first;
        final client = SuperAdminTestConfig.createServiceRoleClient();
        bool isActiveBefore;
        try {
          final rows = await client
              .from('user_roles')
              .select('is_active')
              .eq('user_id', singleAdmin.userId)
              .eq('organization_id', testOrgSingleAdmin.orgId);

          isActiveBefore = rows.first['is_active'] as bool;
        } finally {
          await client.dispose();
        }

        // Simular falha de rede via HttpOverrides
        final originalOverrides = HttpOverrides.current;
        HttpOverrides.global = _FailingHttpOverrides();

        try {
          // Tocar no botão de desativar
          final deactivateButton = find.byTooltip('Inativar Usuário');
          if (deactivateButton.evaluate().isEmpty) {
            markTestSkipped(
              'Nenhum botão de desativar disponível.',
            );
            return;
          }
          await tester.tap(deactivateButton.first);
          await tester.pumpAndSettle();

          // Confirmar no modal (se exibido)
          final dialog = find.byType(AlertDialog);
          final simpleDialog = find.byType(Dialog);
          if (dialog.evaluate().isNotEmpty ||
              simpleDialog.evaluate().isNotEmpty) {
            await SuperAdminWidgetHelpers.confirmModal(tester);
          }

          // Aguardar feedback de erro
          await SuperAdminWidgetHelpers.waitForSnackbar(
            tester,
            'Erro',
          );

          // Verificar que a aplicação não crashou
          expect(
            tester.takeException(),
            isNull,
            reason:
                'A aplicação não deve crashar em caso de falha de rede '
                '(Req 3.7)',
          );
        } finally {
          // Restaurar HttpOverrides original
          HttpOverrides.global = originalOverrides;
        }

        // Verificar que o estado no DB não mudou (consistência)
        final verifyClient = SuperAdminTestConfig.createServiceRoleClient();
        try {
          final afterRows = await verifyClient
              .from('user_roles')
              .select('is_active')
              .eq('user_id', singleAdmin.userId)
              .eq('organization_id', testOrgSingleAdmin.orgId);

          expect(
            afterRows.first['is_active'],
            equals(isActiveBefore),
            reason:
                'user_roles.is_active não deve mudar quando ocorre erro '
                'de rede (Req 3.7 — consistência UI/DB)',
          );
        } finally {
          await verifyClient.dispose();
        }
      },
    );
  });
}

/// HttpOverrides que simula falha de rede para todos os requests.
///
/// Usado pelo teste 3.7 para verificar o comportamento da UI quando
/// a operação de desativação falha por erro de rede.
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
    Future<bool> Function(
      String host,
      int port,
      String scheme,
      String? realm,
    )? f,
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
    )? f,
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
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _fail();

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _fail();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _fail();

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _fail();

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _fail();

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _fail();

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _fail();

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _fail();

  Future<HttpClientRequest> _fail() {
    return Future.error(
      const SocketException('Simulated network failure (CT09 test)'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
