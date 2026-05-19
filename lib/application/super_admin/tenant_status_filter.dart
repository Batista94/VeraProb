/// UI-scoped filter for the tenant list panel.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// This enum lives in the application layer so that `lib/features/` never
/// needs to import [OrgStatus] from `lib/domain/` for filtering purposes.
///
/// The mapping to actual domain status is performed inside
/// [TenantStatusFilter.matches], which knows how to evaluate a
/// [TenantHealthView]'s `isActive` and `isArchived` flags without exposing
/// [OrgStatus] to the presentation layer.
enum TenantStatusFilter {
  all,
  active,
  suspended,
  archived;

  String get label {
    switch (this) {
      case TenantStatusFilter.all:
        return 'Todos';
      case TenantStatusFilter.active:
        return 'Ativos';
      case TenantStatusFilter.suspended:
        return 'Suspensos';
      case TenantStatusFilter.archived:
        return 'Arquivadas';
    }
  }

  bool matches({required bool isActive, required bool isArchived}) {
    switch (this) {
      case TenantStatusFilter.all:
        return true;
      case TenantStatusFilter.active:
        return isActive;
      case TenantStatusFilter.suspended:
        return !isActive && !isArchived;
      case TenantStatusFilter.archived:
        return isArchived;
    }
  }
}
