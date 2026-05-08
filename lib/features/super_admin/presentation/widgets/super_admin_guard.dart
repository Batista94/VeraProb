import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/config/environment.dart';
import 'package:veraprob/core/utils/jwt_utils.dart';
import 'package:veraprob/features/super_admin/presentation/screens/mfa_challenge_screen.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/mfa_disabled_banner.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/not_found_page.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/impersonation_session_provider.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';

/// Zero-Trust guard for the SuperAdmin portal.
///
/// Implements defense-in-depth with the following validation hierarchy:
///
/// 1. `!isSuperAdmin` → [NotFoundPage] + `log-security-incident` RPC (INV-26)
/// 2. `!isAal2 && !skipMfa` → Redirect to [MfaChallengeScreen]
/// 3. `!isAal2 && skipMfa` → child wrapped in [MfaDisabledBanner]
/// 4. Impersonation Actor_ID mismatch → [NotFoundPage] + log
/// 5. Impersonation session expired → Redirect to SuperAdmin home
/// 6. All valid → render [child]
///
/// **Fail-Fast (INV-6):** No child widget (including shimmer/skeleton) is
/// rendered until ALL validations pass.
///
/// **INV-26 (Error Parity):** Unauthorized access renders a generic 404 page
/// indistinguishable from a genuinely missing route.
///
/// **INV-30 (DI Total):** Consumes session exclusively via
/// [isSuperAdminProvider], [isSuperAdminAal2Provider], and
/// [authStateProvider] — no direct Supabase client instantiation.
class SuperAdminGuard extends ConsumerStatefulWidget {
  final Widget child;

  const SuperAdminGuard({super.key, required this.child});

  @override
  ConsumerState<SuperAdminGuard> createState() => _SuperAdminGuardState();
}

class _SuperAdminGuardState extends ConsumerState<SuperAdminGuard> {
  /// Tracks whether an impersonation invalidation is in progress to
  /// prevent the rebuild (caused by clearing the session state) from
  /// rendering the child widget.
  bool _impersonationInvalidated = false;

  @override
  Widget build(BuildContext context) {
    // ── Step 1: Validate super_admin claim ──────────────────────────────
    final isSuperAdmin = ref.watch(isSuperAdminProvider);

    if (!isSuperAdmin) {
      // Fire-and-forget: log the security incident via RPC.
      _logSecurityIncident(eventType: 'SECURITY_VIOLATION_BYPASS_ATTEMPT');
      return const NotFoundPage();
    }

    // ── Step 2: Validate AAL2 (MFA) ────────────────────────────────────
    final isAal2 = ref.watch(isSuperAdminAal2Provider);

    if (!isAal2) {
      // Dev environment with MFA skip → render child with warning banner.
      if (EnvironmentConfig.skipMfaForSuperAdmin) {
        return MfaDisabledBanner(child: widget.child);
      }

      // Production: redirect to MFA challenge (Fail-Fast — no child rendered).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MfaChallengeScreen()),
            (_) => false,
          );
        }
      });
      return const Scaffold();
    }

    // ── Step 3: Validate impersonation session (if active) ─────────────
    final impersonationSession = ref.watch(activeImpersonationSessionProvider);

    // If we've already invalidated the session, keep blocking until
    // navigation completes (prevents child flash during rebuild).
    if (_impersonationInvalidated) {
      return const Scaffold();
    }

    if (impersonationSession != null) {
      // 3a. Actor_ID mismatch check
      final currentUserId = ref
          .watch(authStateProvider)
          .value
          ?.session
          ?.user
          .id;

      if (currentUserId != null &&
          impersonationSession.impersonatorId != currentUserId) {
        // Mismatch: log incident and schedule session cleanup.
        _logSecurityIncident(
          eventType: 'SECURITY_VIOLATION_IMPERSONATION_MISMATCH',
        );
        _invalidateImpersonationSession();
        return const NotFoundPage();
      }

      // 3b. Session expiration check
      if (impersonationSession.isExpired) {
        _invalidateImpersonationSession();
        return const Scaffold();
      }
    }

    // ── Step 4: All validations passed — render child ──────────────────
    return widget.child;
  }

  /// Schedules impersonation session cleanup and navigation.
  ///
  /// Sets [_impersonationInvalidated] to prevent the rebuild (triggered
  /// by clearing the session state) from rendering the child widget.
  void _invalidateImpersonationSession() {
    _impersonationInvalidated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeImpersonationSessionProvider.notifier).set(null);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  /// Fires a `log-security-incident` RPC call asynchronously.
  ///
  /// Extracts sanitized JWT claims from the current session for the
  /// forensic record. Silent on failure (INV-26).
  void _logSecurityIncident({required String eventType}) {
    final session = ref.read(authStateProvider).value?.session;
    final sanitizedClaims = _sanitizeJwtClaims(session?.accessToken);

    ref
        .read(securityIncidentLoggerProvider)
        .log(
          eventType: eventType,
          metadata: {
            'route_attempted': 'super-admin',
            'source': 'flutter_guard',
          },
          jwtClaimsSnapshot: sanitizedClaims,
        );
  }

  /// Sanitizes JWT claims for forensic logging.
  ///
  /// Preserves only: `sub`, `aal`, `role`, `app_metadata.{super_admin, org_id}`.
  /// Removes access/refresh tokens and all other fields.
  static Map<String, dynamic> _sanitizeJwtClaims(String? accessToken) {
    if (accessToken == null) return {};

    try {
      final claims = decodeJwtPayload(accessToken);
      final sanitized = <String, dynamic>{};

      if (claims.containsKey('sub')) sanitized['sub'] = claims['sub'];
      if (claims.containsKey('aal')) sanitized['aal'] = claims['aal'];
      if (claims.containsKey('role')) sanitized['role'] = claims['role'];

      final appMeta = claims['app_metadata'] as Map<String, dynamic>?;
      if (appMeta != null) {
        final sanitizedMeta = <String, dynamic>{};
        if (appMeta.containsKey('super_admin')) {
          sanitizedMeta['super_admin'] = appMeta['super_admin'];
        }
        if (appMeta.containsKey('org_id')) {
          sanitizedMeta['org_id'] = appMeta['org_id'];
        }
        sanitized['app_metadata'] = sanitizedMeta;
      }

      return sanitized;
    } catch (_) {
      return {};
    }
  }
}
