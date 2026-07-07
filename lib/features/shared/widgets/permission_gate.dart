import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/state/providers/auth_providers.dart';

/// Declarative permission gate: renders [child] only when the current session
/// holds [permission] (or the wildcard). Otherwise renders [fallback]
/// (nothing by default).
///
/// Hides rather than disables — a control the user can never use is noise, and
/// hiding it shrinks the attack surface (ux-standards). UX/defense-in-depth
/// only: RLS and the SECURITY DEFINER RPCs remain the source of truth. Derives
/// from [permissionServiceProvider], which recomputes on every auth change, so
/// a user switch re-evaluates the gate automatically (no stale RAM cache).
class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
    this.resourceId,
  });

  final String permission;
  final Widget child;
  final Widget fallback;

  /// Optional resource scope. When set, the permission must be held AND either
  /// unrestricted or scoped to include this id (mirrors `has_permission_on`).
  final String? resourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(permissionServiceProvider);
    final allowed = resourceId == null
        ? service.hasPermission(permission)
        : service.hasPermissionOn(permission, resourceId!);
    return allowed ? child : fallback;
  }
}
