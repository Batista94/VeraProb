import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    // Buscar o texto da organização na lista.
    final orgFinder = find.text(orgName);

    // Se não encontrar imediatamente, pode ser necessário scroll.
    // Primeiro, verificar se está visível.
    if (orgFinder.evaluate().isEmpty) {
      // Tentar scroll na lista para encontrar o item.
      final listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          orgFinder,
          200,
          scrollable: find.descendant(
            of: listView.first,
            matching: find.byType(Scrollable),
          ),
        );
      }
    }

    expect(
      orgFinder,
      findsAtLeast(1),
      reason: 'A organização "$orgName" deve estar visível na lista de tenants',
    );

    await tester.tap(orgFinder.first);
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
    final usersTab = find.text('Usuários');

    expect(
      usersTab,
      findsAtLeast(1),
      reason: 'A aba "Usuários" deve estar visível no TabBar do detalhe da org',
    );

    // A tab "Usuários" é um widget Tab dentro do TabBar.
    // Toca no texto para selecionar a aba.
    await tester.tap(usersTab.first);
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
    final archivedChip = find.widgetWithText(FilterChip, 'Suspensos');

    expect(
      archivedChip,
      findsOneWidget,
      reason: 'O FilterChip "Suspensos" deve estar visível na lista de tenants',
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
