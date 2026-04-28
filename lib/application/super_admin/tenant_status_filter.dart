/// UI-scoped filter for the tenant list panel.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// This enum lives in the application layer so that `lib/features/` never
/// needs to import [OrgStatus] from `lib/domain/` for filtering purposes.
///
/// The mapping to actual domain status is performed inside
/// [TenantStatusFilter.matches], which knows how to evaluate a
/// [TenantHealthView]'s `isActive` flag without exposing [OrgStatus] to the
/// presentation layer.
enum TenantStatusFilter {
  /// Show all tenants regardless of status.
  all,

  /// Show only currently active organizations.
  active,

  /// Show only suspended organizations.
  suspended;

  /// Human-readable label for display in filter chips.
  String get label {
    switch (this) {
      case TenantStatusFilter.all:
        return 'Todos';
      case TenantStatusFilter.active:
        return 'Ativos';
      case TenantStatusFilter.suspended:
        return 'Suspensos';
    }
  }

  /// Returns `true` when a tenant should be included in the filtered list.
  ///
  /// Uses only presentation-level primitives (`isActive` bool from
  /// [TenantHealthView]) — no domain enum comparison needed.
  bool matches({required bool isActive}) {
    switch (this) {
      case TenantStatusFilter.all:
        return true;
      case TenantStatusFilter.active:
        return isActive;
      case TenantStatusFilter.suspended:
        return !isActive;
    }
  }
}
