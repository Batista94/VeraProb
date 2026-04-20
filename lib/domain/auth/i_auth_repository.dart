import 'package:veraprob/domain/auth/auth_failure_exception.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

/// Port for authentication operations.
///
/// Concrete implementation: [SupabaseAuthRepository].
/// INV-18: Pure Dart interface — zero infrastructure dependencies.
/// INV-6: SuperAdmin sign-out clears the MFA AAL2 session.
abstract class IAuthRepository {
  /// Returns true if there is an active session (synchronous read).
  bool get isAuthenticated;

  /// Stream of authentication status changes.
  ///
  /// Emits `true` on sign-in and `false` on sign-out.
  /// Replaces direct `auth.onAuthStateChange` subscriptions in widgets.
  Stream<bool> get authStatusStream;

  /// Signs in with email and password.
  ///
  /// Returns the [userId] on success.
  /// Throws [AuthFailureException] if the provider returns no user
  /// or if authentication fails (credentials, network, etc.).
  Future<String> signInWithPassword({
    required String email,
    required String password,
  });

  /// Signs up a new user with email and password.
  ///
  /// Returns the [userId] on success.
  /// Throws [AuthFailureException] if the provider returns no user
  /// or if registration fails (weak password, email conflict, etc.).
  Future<String> signUpWithPassword({
    required String email,
    required String password,
  });

  /// Signs out the current user from all sessions (global sign-out).
  ///
  /// Uses [GlobalSignOutScope] to invalidate tokens on all devices,
  /// preventing session replay attacks.
  Future<void> signOut();

  /// Refreshes the JWT session.
  ///
  /// Re-triggers the `custom_access_token_hook` so that
  /// `organization_id` and `role` claims are re-injected into the token.
  /// Called after invitation acceptance to hydrate the new JWT claims.
  ///
  /// Throws [AuthFailureException] if the refresh fails (expired token,
  /// network error, etc.).
  Future<void> refreshSession();

  /// Returns the current authenticated user as a domain [AuthUser].
  ///
  /// Extracts [tenantId] EXCLUSIVELY from `app_metadata['org_id']`
  /// (injected by `custom_access_token_hook`), ensuring [INV-1] compliance.
  ///
  /// Returns `null` if there is no active session.
  /// Throws [AuthFailureException] if the user lacks `org_id` in
  /// `app_metadata` (tenant isolation violation).
  Future<AuthUser?> getCurrentUser();

  /// Resolves an [AuthUser] from a session identifier.
  ///
  /// Used by [TenantValidationService] to perform the Fail-Fast Identity
  /// Sync check (INV-1): comparing `payload.org_id` against `jwt.org_id`.
  ///
  /// Returns `null` if the session does not exist or is expired.
  /// Throws [SovereigntyViolationException] if the session is invalid
  /// and a payload org_id was provided (indicates a spoofing attempt).
  Future<AuthUser?> getUserBySessionId(String sessionId);
}
