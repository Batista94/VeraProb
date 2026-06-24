import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/state/providers/auth_providers.dart';

/// Resilient session recovery utilities for command paths.
///
/// Many action handlers check `currentOrganizationIdProvider` and immediately
/// declare "Sessão expirada" if it returns `null`. However, the session might
/// still be salvageable via a token refresh — the JWT may have just expired
/// while the user was actively working (e.g., mapping CSV columns).
///
/// This utility encapsulates the "attempt refresh before giving up" pattern
/// to avoid duplicating the same recovery logic across every provider/screen.
class SessionRecovery {
  /// Attempts to resolve the current organization ID from a [Ref] context
  /// (Notifiers, providers).
  ///
  /// 1. Reads `currentOrganizationIdProvider` — if non-null, returns it.
  /// 2. If null, attempts `refreshSession()` and reads again.
  /// 3. If still null after refresh, returns `null` (truly expired).
  static Future<String?> ensureOrgId(Ref ref) async {
    var orgId = ref.read(currentOrganizationIdProvider);
    if (orgId != null) return orgId;

    // Attempt proactive token refresh
    try {
      await ref.read(authRepositoryProvider).refreshSession();
    } catch (_) {
      // Refresh failed — session is truly dead
      return null;
    }

    // Re-read after refresh — the StreamProvider should have updated
    orgId = ref.read(currentOrganizationIdProvider);
    return orgId;
  }

  /// Attempts to resolve the current organization ID from a [WidgetRef] context
  /// (Widget build methods, callbacks).
  static Future<String?> ensureOrgIdWidget(WidgetRef ref) async {
    var orgId = ref.read(currentOrganizationIdProvider);
    if (orgId != null) return orgId;

    try {
      await ref.read(authRepositoryProvider).refreshSession();
    } catch (_) {
      return null;
    }

    orgId = ref.read(currentOrganizationIdProvider);
    return orgId;
  }

  /// Attempts to resolve both org ID and session (access token) from [Ref].
  ///
  /// Returns a record `(orgId, sessionId)` or `null` if unrecoverable.
  static Future<({String orgId, String sessionId})?> ensureSession(
    Ref ref,
  ) async {
    var orgId = ref.read(currentOrganizationIdProvider);
    var sessionId = ref.read(currentSessionIdProvider);

    if (orgId != null && sessionId != null) {
      return (orgId: orgId, sessionId: sessionId);
    }

    // Attempt proactive token refresh
    try {
      await ref.read(authRepositoryProvider).refreshSession();
    } catch (_) {
      return null;
    }

    orgId = ref.read(currentOrganizationIdProvider);
    sessionId = ref.read(currentSessionIdProvider);

    if (orgId != null && sessionId != null) {
      return (orgId: orgId, sessionId: sessionId);
    }

    return null;
  }

  /// Attempts to resolve both org ID and session from [WidgetRef].
  static Future<({String orgId, String sessionId})?> ensureSessionWidget(
    WidgetRef ref,
  ) async {
    var orgId = ref.read(currentOrganizationIdProvider);
    var sessionId = ref.read(currentSessionIdProvider);

    if (orgId != null && sessionId != null) {
      return (orgId: orgId, sessionId: sessionId);
    }

    try {
      await ref.read(authRepositoryProvider).refreshSession();
    } catch (_) {
      return null;
    }

    orgId = ref.read(currentOrganizationIdProvider);
    sessionId = ref.read(currentSessionIdProvider);

    if (orgId != null && sessionId != null) {
      return (orgId: orgId, sessionId: sessionId);
    }

    return null;
  }
}
