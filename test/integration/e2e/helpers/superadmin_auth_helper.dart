import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_detail_panel.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_list_panel.dart';
import 'package:veraprob/main.dart' as app;

import 'superadmin_test_config.dart';

/// Helper de autenticação para os testes E2E do SuperAdmin.
///
/// Responsável por:
/// - Login via UI (email + senha) com `SKIP_MFA_DEV=true`
/// - Verificação de sessão ativa
/// - Forçar expiração de token para cenários adversos
/// - Verificar ausência de dados sensíveis na tela (anti "Flash de Dados")
///
/// Todas as operações assumem que a aplicação foi iniciada com
/// `--dart-define=SKIP_MFA_DEV=true` para bypass de MFA em ambiente de teste.
///
/// **Validates: Requirements 1.3, 8.5**
abstract class SuperAdminAuthHelper {
  /// Realiza login como SuperAdmin via interação de UI.
  ///
  /// Fluxo:
  /// 1. Localiza o campo de email e insere [SuperAdminTestConfig.superAdminEmail]
  /// 2. Localiza o campo de senha e insere [SuperAdminTestConfig.superAdminPassword]
  /// 3. Toca no botão de login
  /// 4. Aguarda navegação completar (pumpAndSettle com timeout)
  ///
  /// A aplicação deve estar rodando com `SKIP_MFA_DEV=true` para que o MFA
  /// seja automaticamente bypassado após o login.
  ///
  /// Lança [TestFailure] se o login não completar dentro do timeout.
  static Future<void> loginAsSuperAdmin(WidgetTester tester) async {
    // Sessão residual entre testes sequenciais: Supabase.instance é singleton
    // na Dart VM e preserva currentSession. Sem signOut, AdminLockScreen
    // auto-redireciona ao SuperAdminShell e o helper não encontra os 2 campos
    // de login (falso positivo em CT09/CT12/CT16).
    if (await isSessionActive()) {
      await forceTokenExpiry();
    }

    final hmacKey = SuperAdminTestConfig.hmacSecretKeyV1;
    SharedPreferences.setMockInitialValues({
      'hmac_request_key_v1': hmacKey.isNotEmpty
          ? hmacKey
          : 'test-hmac-key-v1-32chars-padding00',
    });

    // Mock app_links EventChannel — native plugin unavailable in flutter test VM.
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}, onCancel: (_) {}),
    );

    // ErrorBoundary (lib/features/shared/widgets/error_boundary.dart:23) reatribui
    // ErrorWidget.builder global em initState sem restaurar. flutter_test verifica
    // drift dentro de _runTestBody (antes dos teardowns), então addTearDown roda
    // tarde demais. Captura o builder vigente (do flutter_test) antes de app.main()
    // e restaura logo após pumpAndSettle — ErrorBoundary só mounta 1x na vida do
    // app, não há risco de re-trigger.
    final originalErrorWidgetBuilder = ErrorWidget.builder;

    app.main();
    await tester.pumpAndSettle();

    ErrorWidget.builder = originalErrorWidgetBuilder;

    // Fail fast: empty dart-defines cause SupabaseConfig.initialize() to return
    // silently. PostgresTestConfig falls back to .env via dart:io, so
    // isSupabaseRunning() returns true and tests are not skipped — but
    // Supabase.instance is never initialized. Detect this here and emit an
    // actionable message instead of a cryptic AssertionError later.
    try {
      Supabase.instance.client;
    } catch (_) {
      fail(
        'Supabase singleton not initialized after app.main().\n'
        'Run E2E tests via the Makefile:\n'
        '  make test-e2e\n'
        '  make test-e2e-file FILE=<path>\n'
        'or pass all required dart-defines explicitly:\n'
        '  --dart-define=SUPABASE_URL=<url>\n'
        '  --dart-define=SUPABASE_KEY=<anon_key>\n'
        '  --dart-define=SKIP_MFA_DEV=true\n'
        '  --dart-define=ENV=dev',
      );
    }

    // Localizar campos de email e senha.
    // O padrão da UI usa TextField com InputDecoration contendo hintText
    // ou labelText. Buscamos por tipo e posição (primeiro = email, segundo = senha).
    final textFields = find.byType(TextField);

    // Aguardar que a tela de login esteja renderizada.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 500),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );

    expect(
      textFields,
      findsAtLeast(2),
      reason: 'Tela de login deve conter pelo menos 2 campos (email + senha)',
    );

    // Campo de email (primeiro TextField).
    await tester.enterText(
      textFields.first,
      SuperAdminTestConfig.superAdminEmail,
    );
    await tester.pump();

    // Campo de senha (segundo TextField).
    await tester.enterText(
      textFields.at(1),
      SuperAdminTestConfig.superAdminPassword,
    );
    await tester.pump();

    // Localizar e tocar no botão de login.
    // Busca por ElevatedButton ou FilledButton habilitado.
    final loginButton = find.byWidgetPredicate((widget) {
      if (widget is ElevatedButton) return widget.enabled;
      if (widget is FilledButton) return widget.enabled;
      return false;
    });

    // Fallback: buscar por texto comum de botão de login.
    final loginByText = find.widgetWithText(ElevatedButton, 'Entrar');
    final loginByTextFilled = find.widgetWithText(FilledButton, 'Entrar');
    final loginByTextSystem = find.widgetWithText(
      ElevatedButton,
      'ACESSAR SISTEMA',
    );

    Finder buttonFinder;
    if (loginByTextSystem.evaluate().isNotEmpty) {
      buttonFinder = loginByTextSystem;
    } else if (loginByText.evaluate().isNotEmpty) {
      buttonFinder = loginByText;
    } else if (loginByTextFilled.evaluate().isNotEmpty) {
      buttonFinder = loginByTextFilled;
    } else {
      // Último recurso: primeiro botão habilitado na tela.
      buttonFinder = loginButton;
    }

    expect(
      buttonFinder,
      findsAtLeast(1),
      reason: 'Deve existir um botão de login habilitado na tela',
    );

    await tester.tap(buttonFinder.first);

    // Aguardar navegação pós-login (inclui possível redirect do SuperAdminGuard).
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }

  /// Verifica se existe uma sessão de autenticação ativa no Supabase.
  ///
  /// Retorna `true` se `currentSession` não é nulo e o token de acesso
  /// ainda está presente. Não valida expiração do JWT — apenas presença.
  ///
  /// Retorna `false` se o singleton ainda não foi inicializado (dart-defines
  /// ausentes / SupabaseConfig.initialize() pulado silenciosamente).
  static Future<bool> isSessionActive() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      return session != null && session.accessToken.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Força a expiração/invalidação da sessão para cenários adversos.
  ///
  /// Estratégia: executa `signOut()` no cliente Supabase, o que:
  /// 1. Invalida o refresh token no servidor
  /// 2. Limpa a sessão local (SharedPreferences)
  /// 3. Dispara o `onAuthStateChange` com evento `signedOut`
  ///
  /// Após esta chamada, qualquer widget observando [authStateProvider]
  /// deve reagir e redirecionar para a tela de login.
  ///
  /// Para testes que precisam simular expiração sem signOut explícito
  /// (ex: token expirado pelo servidor), use em conjunto com
  /// [assertNoSensitiveDataVisible] para verificar o anti-flash.
  static Future<void> forceTokenExpiry() async {
    await Supabase.instance.client.auth.signOut();
  }

  /// Verifica que nenhum dado sensível de organização está visível na tela.
  ///
  /// Usado após [forceTokenExpiry] para garantir que a UI limpa dados
  /// sensíveis ANTES do redirect para login (anti "Flash de Dados").
  ///
  /// Verifica ausência de:
  /// - Nomes de organizações (via TenantDetailPanel / TenantListPanel)
  /// - Padrões de CNPJ (XX.XXX.XXX/XXXX-XX ou 14 dígitos consecutivos)
  /// - Telas de detalhe de tenant (TenantDetailPanel)
  ///
  /// Lança [TestFailure] se qualquer dado sensível for encontrado.
  ///
  /// **Validates: Requirement 8.5** (anti "Flash de Dados")
  static Future<void> assertNoSensitiveDataVisible(WidgetTester tester) async {
    // Pump para garantir que o estado mais recente está renderizado.
    await tester.pump();

    // 1. Verificar ausência de TenantDetailPanel (tela de detalhe de org).
    expect(
      find.byType(TenantDetailPanel),
      findsNothing,
      reason:
          'TenantDetailPanel não deve estar visível após expiração de token '
          '(anti "Flash de Dados")',
    );

    // 2. Verificar ausência de TenantListPanel (listagem de orgs).
    expect(
      find.byType(TenantListPanel),
      findsNothing,
      reason:
          'TenantListPanel não deve estar visível após expiração de token '
          '(anti "Flash de Dados")',
    );

    // 3. Verificar ausência de padrões de CNPJ formatado (XX.XXX.XXX/XXXX-XX).
    final cnpjFormatted = find.textContaining(
      RegExp(r'\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}'),
    );
    expect(
      cnpjFormatted,
      findsNothing,
      reason:
          'CNPJs formatados não devem estar visíveis após expiração de token',
    );

    // 4. Verificar ausência de padrões de CNPJ não-formatado (14 dígitos).
    // Evita falsos positivos filtrando apenas textos que são exatamente 14 dígitos.
    final cnpjRaw = find.byWidgetPredicate((widget) {
      if (widget is Text && widget.data != null) {
        return RegExp(r'^\d{14}$').hasMatch(widget.data!.trim());
      }
      return false;
    });
    expect(
      cnpjRaw,
      findsNothing,
      reason:
          'CNPJs (14 dígitos) não devem estar visíveis após expiração de token',
    );
  }
}
