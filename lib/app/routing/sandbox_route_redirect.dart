import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/app/routing/routing_utils.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';

/// UUID integrity redirect for SLA Sandbox paths.
///
/// RBAC is enforced by [requiredPermissionFor] + [rbacRouteRedirect].
/// Returns a redirect target, or `null` to proceed.
String? sandboxRouteRedirect(String path) {
  if (path == '/admin/hub/contracts/sandbox') {
    return AdminNavRoute(AdminNav.contracts).path;
  }

  final match = sandboxContractPathPattern.firstMatch(path);
  if (match == null) return null;

  if (parseContractIdParam(match.group(1)) == null) {
    return AdminNavRoute(AdminNav.contracts).path;
  }

  return null;
}
