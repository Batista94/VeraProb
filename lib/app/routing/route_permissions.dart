import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/app/routing/routing_utils.dart';

/// Static route → required-permission gate for the admin shell (Pilar 3).
///
/// A path present here (exact or as a prefix segment) requires the mapped
/// fine-grained permission key. Absent paths are ungated. This is the single
/// source shared by the GoRouter redirect guard ([appRouterProvider]) and the
/// sidebar/hub visibility filters — UX/defense-in-depth only. RLS and the
/// SECURITY DEFINER RPCs remain the source of truth; a spoofed client cannot
/// read tenant data by bypassing this map.
///
/// Parity rule for new entries: gate a route here only when the backend also
/// enforces that permission per-route (RLS/RPC). Per-action gates
/// (`sla:approve`, `financial:export`) and query-param tabs (`roles:manage` on
/// `settings?tab=access`, already blocked in the screen + RPCs) stay out —
/// gating them here would break UI↔backend parity.
const Map<String, String> kRoutePermissions = <String, String>{
  '/admin/financial-impact': 'financial:read',
  '/admin/hub/billing-reports': 'financial:read',
};

/// Permission required to view [path], or `null` when the route is ungated.
///
/// Matches on the exact path or a `${key}/` prefix so nested deep links inherit
/// their parent's gate (e.g. a future `/admin/hub/billing-reports/:id`).
String? requiredPermissionFor(String path) {
  if (parseSandboxContractIdFromPath(path) != null) {
    return 'sandbox:simulate';
  }

  for (final entry in kRoutePermissions.entries) {
    final key = entry.key;
    if (path == key || path.startsWith('$key/')) {
      return entry.value;
    }
  }
  return null;
}

/// Pure RBAC decision for the GoRouter redirect. Returns the silent-eject
/// target ([AppRoutes.adminHub], anti-oracle INV-26) when [perms] lack the
/// permission [path] requires, invoking [onDenied] with the attempted route +
/// missing key so the caller can fire the ACCESS_DENIED audit. Returns `null`
/// (proceed) when the route is ungated or the permission — or the `'*'`
/// wildcard — is held. UX/defense-in-depth only; RLS/RPCs stay authoritative.
String? rbacRouteRedirect(
  String path,
  Iterable<String> perms, {
  required void Function(String route, String requiredPerm) onDenied,
}) {
  final required = requiredPermissionFor(path);
  if (required == null) return null;
  if (perms.contains('*') || perms.contains(required)) return null;
  onDenied(path, required);
  return AppRoutes.adminHub;
}
