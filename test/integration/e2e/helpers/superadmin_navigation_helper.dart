import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_list_panel.dart';

import 'superadmin_test_config.dart';

/// Helpers de navegação para o painel SuperAdmin.
///
/// Encapsula interações de UI para navegar entre as telas do painel:
/// - Lista de organizações (via NavigationRail)
/// - Detalhe de uma organização (via tap no item da lista)
/// - Aba "Usuários" (via TabBar no detalhe)
/// - Filtros de status (via FilterChip na lista)
///
/// Todas as operações usam [SuperAdminTestConfig.defaultTimeout] para
/// `pumpAndSettle`, garantindo que a navegação complete antes de prosseguir.
///
/// **Validates: Requirement 1.3**
abstract class SuperAdminNavigationHelper {
  /// Navega até a listagem de organizações (Tenants).
  ///
  /// Toca no item "Tenants" do [NavigationRail] no shell do SuperAdmin.
  /// Aguarda a lista renderizar via `pumpAndSettle`.
  ///
  /// Pré-condição: o SuperAdmin já está autenticado e o shell está visível.
  static Future<void> goToTenantList(WidgetTester tester) async {
    // O NavigationRail possui um destino com label "Tenants" (index 0).
    // Buscar pelo texto "Tenants" dentro do NavigationRail.
    final tenantsDest = find.text('Tenants');

    expect(
      tenantsDest,
      findsAtLeast(1),
      reason:
          'O item "Tenants" deve estar visível no NavigationRail do SuperAdmin',
    );

    await tester.tap(tenantsDest.first);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }

  /// Navega até os detalhes de uma organização específica.
  ///
  /// A partir da lista de tenants, localiza o [ListTile] cujo título
  /// contém [orgName] e toca nele para abrir o painel de detalhes.
  ///
  /// Pré-condição: a lista de tenants está visível (chamar [goToTenantList]
  /// antes se necessário).
  ///
  /// Lança [TestFailure] se a organização não for encontrada na lista.
  static Future<void> goToTenantDetail(
    WidgetTester tester,
    String orgName,
  ) async {
    // Settle any pending navigation animations.
    await tester.pump(const Duration(milliseconds: 100));

    // Wait until the tenant list finishes loading.
    // pumpAndSettle can return "settled" before the Supabase FutureProvider
    // resolves: HTTP in-flight = no Flutter work pending → early settle,
    // leaving the skeleton visible and tenantListViewKey absent. An explicit
    // pump loop gives the real HTTP call time to complete.
    final sw = Stopwatch()..start();
    while (find.byKey(TenantListPanel.tenantListViewKey).evaluate().isEmpty &&
        find.byKey(TenantListPanel.tenantListErrorKey).evaluate().isEmpty &&
        sw.elapsed < SuperAdminTestConfig.defaultTimeout) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Fail fast when the panel is in error state (GoTrue HTTP 500 / banned_until=infinity).
    // Without this guard the test fails with a misleading "org not found in list"
    // instead of the real cause: the API call failed before the list rendered.
    final errorPanel = find.byKey(TenantListPanel.tenantListErrorKey);
    if (errorPanel.evaluate().isNotEmpty) {
      fail(
        'TenantListPanel is in error state while navigating to "$orgName". '
        'GoTrue may be returning HTTP 500 — verify no auth.users rows have '
        'banned_until = infinity (run migration '
        '20260519000001_fix_banned_until_infinity).',
      );
    }

    // Buscar o texto da organização na lista.
    final orgFinder = find.text(orgName);

    // Se não encontrar imediatamente, pode ser necessário scroll.
    // Drag the keyed ListView directly — avoids scrollUntilVisible's
    // Scrollable stability requirement (which throws "Bad state: No element"
    // when the list rebuilds mid-scroll, e.g. on first data arrival).
    if (orgFinder.evaluate().isEmpty) {
      final listView = find.byKey(TenantListPanel.tenantListViewKey);
      if (listView.evaluate().isNotEmpty) {
        for (int i = 0; i < 20 && orgFinder.evaluate().isEmpty; i++) {
          await tester.drag(listView.first, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
    }

    expect(
      orgFinder,
      findsAtLeast(1),
      reason: 'A organização "$orgName" deve estar visível na lista de tenants',
    );

    // O Text fica dentro de ListTile (lib/features/super_admin/presentation/
    // screens/tenant_list_panel.dart:245). Tap direto no Text falha hittest
    // porque o InkWell do ListTile não cobre o filho. Subir até o ListTile.
    final tappableTile = find
        .ancestor(of: orgFinder.first, matching: find.byType(ListTile))
        .first;

    // ensureVisible garante que o ListTile esteja dentro do viewport antes
    // do tap. Em viewport 800x600 (default flutter_test), tiles após o
    // ~7º item ficam off-screen e tap falha hittest mesmo no ancestor.
    await tester.ensureVisible(tappableTile);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );

    await tester.tap(tappableTile);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }

  /// Navega até a aba "Usuários" dentro do painel de detalhes de uma org.
  ///
  /// Toca na tab "Usuários" do [TabBar] no [TenantDetailPanel].
  /// A tab está no índice 4 (Métricas=0, Saúde Técnica=1, Configuração=2,
  /// Segurança=3, Usuários=4, Auditoria=5).
  ///
  /// Pré-condição: o painel de detalhes de uma organização está visível
  /// (chamar [goToTenantDetail] antes).
  static Future<void> goToUsersTab(WidgetTester tester) async {
    // Escopo para TabBar — sem isso, find.text('Usuários') pode capturar
    // outros widgets (sidebar/etc) ou Tab fora do scroll viewport.
    final usersTabText = find.descendant(
      of: find.byType(TabBar),
      matching: find.text('Usuários'),
    );

    expect(
      usersTabText,
      findsAtLeast(1),
      reason: 'A aba "Usuários" deve estar visível no TabBar do detalhe da org',
    );

    // TabBar é scrollable (tenant_detail_panel.dart:214 isScrollable: true).
    // Em viewport 800x600, tab "Usuários" (índice 4) fica off-screen — log
    // mostrava Offset(877.8, 208.0) fora de Size(800, 600). Tap no texto
    // direto falha hittest. Subir até Tab widget + ensureVisible (rola
    // TabBar interno) antes de tocar.
    final tabFinder = find
        .ancestor(of: usersTabText.first, matching: find.byType(Tab))
        .first;
    await tester.ensureVisible(tabFinder);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );

    await tester.tap(tabFinder);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }

  /// Aplica o filtro "Suspensos" (organizações arquivadas/inativas) na lista.
  ///
  /// Toca no [FilterChip] com label "Suspensos" no [TenantListPanel].
  /// Organizações suspensas/arquivadas possuem `isActive = false`.
  ///
  /// Pré-condição: a lista de tenants está visível.
  static Future<void> filterArchived(WidgetTester tester) async {
    final archivedChip = find.widgetWithText(FilterChip, 'Arquivadas');

    expect(
      archivedChip,
      findsOneWidget,
      reason:
          'O FilterChip "Arquivadas" deve estar visível na lista de tenants',
    );

    await tester.tap(archivedChip);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }

  /// Aplica o filtro "Ativos" (organizações ativas) na lista.
  ///
  /// Toca no [FilterChip] com label "Ativos" no [TenantListPanel].
  ///
  /// Pré-condição: a lista de tenants está visível.
  static Future<void> filterActive(WidgetTester tester) async {
    final activeChip = find.widgetWithText(FilterChip, 'Ativos');

    expect(
      activeChip,
      findsOneWidget,
      reason: 'O FilterChip "Ativos" deve estar visível na lista de tenants',
    );

    await tester.tap(activeChip);
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      SuperAdminTestConfig.defaultTimeout,
    );
  }
}
