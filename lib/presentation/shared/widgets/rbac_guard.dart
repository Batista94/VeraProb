import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// A widget that conditionally renders its child based on the current user's role.
///
/// If the user does not have the [minimumRole], the [fallback] widget is shown.
/// If [fallback] is null, an empty [SizedBox] is returned.
class RbacGuard extends ConsumerWidget {
  final UserRole minimumRole;
  final Widget child;
  final Widget? fallback;

  const RbacGuard({
    super.key,
    required this.minimumRole,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRole = ref.watch(currentUserRoleProvider);

    if (currentRole.hasPermission(minimumRole)) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}
