import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/start_impersonation_handler.dart';

/// Global state for the active impersonation session.
///
/// Holds the current [ImpersonationSessionInfo] when a SuperAdmin is
/// impersonating a tenant, or `null` when no impersonation is active.
///
/// The guard reads this provider to validate Actor_ID match and session
/// expiration. Screens that start/revoke impersonation sessions update
/// this provider accordingly.
///
/// INV-30: No direct Supabase client access — session metadata only.
final activeImpersonationSessionProvider =
    StateProvider<ImpersonationSessionInfo?>((ref) => null);
