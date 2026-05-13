import 'package:flutter/foundation.dart';

/// Semantic tab types for [TenantDetailPanel].
enum TenantTabType { metrics, health, config, security, users, audit }

/// Factory for deterministic, semantic [Key] and identifier generation.
///
/// Combines domain (orgId) + intent (tabType) to produce stable selectors
/// for both widget tests and E2E automation (Playwright/Appium).
class TenantTabKeys {
  TenantTabKeys._();

  /// Widget [Key] for a tab button: `tab-{orgId}-{tabType}`.
  static Key tab(String orgId, TenantTabType type) =>
      Key('tab-$orgId-${type.name}');

  /// Widget [Key] for a tab content panel: `panel-{orgId}-{tabType}`.
  static Key panel(String orgId, TenantTabType type) =>
      Key('panel-$orgId-${type.name}');

  /// Automation identifier string (Playwright `data-testid` equivalent).
  static String identifier(String orgId, TenantTabType type) =>
      'tab-$orgId-${type.name}';

  /// Human-readable label for screen readers (WCAG 2.2).
  static String label(TenantTabType type) => switch (type) {
    TenantTabType.metrics => 'Aba Métricas',
    TenantTabType.health => 'Aba Saúde Técnica',
    TenantTabType.config => 'Aba Configuração',
    TenantTabType.security => 'Aba Segurança',
    TenantTabType.users => 'Aba Usuários',
    TenantTabType.audit => 'Aba Auditoria',
  };

  /// All tab types in display order.
  static const List<TenantTabType> allTabs = TenantTabType.values;
}
