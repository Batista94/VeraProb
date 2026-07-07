/// Pure client-side mirror of the Postgres `public.has_permission` /
/// `public.has_permission_on` O(1) helpers.
///
/// Resolves fine-grained permission checks from claims already materialized in
/// memory from the JWT (`app_metadata.permissions` + `app_metadata.perm_scopes`).
/// Client gating is UX/defense-in-depth only — RLS and SECURITY DEFINER RPCs
/// remain the source of truth (parity guaranteed by shared test cases).
class PermissionService {
  const PermissionService({
    required Set<String> permissions,
    required Map<String, Set<String>> scopes,
  }) : _permissions = permissions,
       _scopes = scopes;

  static const String _wildcard = '*';

  final Set<String> _permissions;
  final Map<String, Set<String>> _scopes;

  /// Mirrors `public.has_permission(perm)`.
  bool hasPermission(String key) =>
      _permissions.contains(_wildcard) || _permissions.contains(key);

  /// Mirrors `public.has_permission_on(perm, resource_id)`: the permission is
  /// held AND either unrestricted (no scope entry) or the resource is allowed.
  bool hasPermissionOn(String key, String resourceId) {
    if (!hasPermission(key)) return false;
    final scope = _scopes[key];
    return scope == null || scope.contains(resourceId);
  }

  /// True if the holder has ANY of [keys] (or the wildcard).
  bool hasAny(Iterable<String> keys) =>
      _permissions.contains(_wildcard) || keys.any(_permissions.contains);

  /// True if the holder has ALL of [keys] (or the wildcard).
  bool hasAll(Iterable<String> keys) =>
      _permissions.contains(_wildcard) || keys.every(_permissions.contains);
}
