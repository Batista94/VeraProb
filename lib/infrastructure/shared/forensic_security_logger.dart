/// Forensic Security Logger for internal SOC observability.
///
/// **Purpose:** Enriches security events with forensic metadata (org IDs,
/// severity tags, attack vectors) for Sentry/SOC consumption — while
/// guaranteeing that NO forensic data leaks to external HTTP responses.
///
/// **Security Contract:**
/// - This class is **side-effect only** (void return methods).
/// - All forensic data flows to Sentry/PostHog for internal audit.
/// - The [SovereigntyErrorMapper] is completely unaware of this class —
///   it always produces indistinguishable `{"error":"Not Found"}` 404s.
///
/// **Event Types:**
/// | Method                              | Severity | Use Case |
/// |-------------------------------------|----------|----------|
/// | `logOriginOwnershipViolation`       | HIGH     | Cross-org resource access attempt (INV-27) |
/// | `logIdentitySpoofing`              | CRITICAL | JWT/Payload org_id mismatch (INV-1) |
///
/// **Usage in Edge Functions / Controllers:**
/// ```dart
/// try {
///   tenantValidationService.verifySourceOwnership(...);
/// } on ResourceNotFoundException {
///   ForensicSecurityLogger.logOriginOwnershipViolation(
///     requesterOrgId: jwtOrgId,
///     resourceOwnerOrgId: fetchedResource.orgId,
///     resourceType: 'contract',
///     resourceId: sourceContractId,
///     attackVector: 'cross_org_clone_attempt',
///   );
///   return sovereigntyErrorResponse(); // INV-26: indistinguishable 404
/// }
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:veraprob/application/shared/security_context.dart';
import 'package:veraprob/infrastructure/config/environment.dart';

/// Static forensic logger for security event auditing.
///
/// All methods send enriched context to Sentry and return void.
/// No data from these calls ever reaches the HTTP response.
class ForensicSecurityLogger {
  ForensicSecurityLogger._();

  // ── Event 1: Origin Ownership Violation (INV-27) ──────────────────────

  /// Logs a cross-org resource access attempt.
  ///
  /// **Triggered when:** Organization A tries to access/clone/transfer a
  /// resource owned by Organization B.
  ///
  /// **SOC Severity:** HIGH — indicates active tenant isolation probing.
  ///
  /// **Forensic Fields:**
  /// - [requesterOrgId]: The org extracted from the attacker's JWT
  /// - [resourceOwnerOrgId]: The actual owner of the target resource
  /// - [resourceType]: Type of resource (contract, asset, sla_template, etc.)
  /// - [resourceId]: The specific resource ID the attacker targeted
  /// - [attackVector]: Optional classification (e.g., 'cross_org_clone_attempt')
  static void logOriginOwnershipViolation({
    required String requesterOrgId,
    required String resourceOwnerOrgId,
    required String resourceType,
    required String resourceId,
    String? attackVector,
    SecurityContext? securityContext,
  }) {
    final message =
        'Origin Ownership Violation: $requesterOrgId attempted to '
        'access $resourceType/$resourceId owned by $resourceOwnerOrgId';

    if (kDebugMode) {
      debugPrint('[FORENSIC SECURITY] $message');
    }

    if (!EnvironmentConfig.sentryEnabled) return;

    // Configure scope tags, then capture the message at Sentry level.
    // Tags persist on the scope; the message is captured separately.
    Sentry.configureScope((scope) {
      scope.level = SentryLevel.warning;
      _applyTags(
        scope,
        securityEvent: 'ORIGIN_OWNERSHIP_VIOLATION',
        severity: 'HIGH',
        requesterOrgId: requesterOrgId,
        resourceOwnerOrgId: resourceOwnerOrgId,
        attackVector: attackVector,
        securityContext: securityContext,
      );
      _applyContext(
        scope,
        resourceType: resourceType,
        resourceId: resourceId,
        attackVector: attackVector,
        securityContext: securityContext,
      );
    });
    Sentry.captureMessage(message);
  }

  // ── Event 2: Identity Spoofing (INV-1) ────────────────────────────────

  /// Logs a JWT/Payload organization ID mismatch (Identity Spoofing).
  ///
  /// **Triggered when:** A request carries a `payload.org_id` that differs
  /// from the authenticated user's JWT `org_id` claim.
  ///
  /// **SOC Severity:** CRITICAL — indicates active identity spoofing or
  /// token manipulation.
  ///
  /// **Forensic Fields:**
  /// - [payloadOrgId]: The org_id claimed in the request body
  /// - [jwtOrgId]: The org_id from the authenticated user's JWT
  /// - [sessionId]: The session identifier (for correlation)
  /// - [attackVector]: Optional classification (e.g., 'replay_attack_with_stolen_token')
  static void logIdentitySpoofing({
    required String payloadOrgId,
    required String jwtOrgId,
    required String sessionId,
    String? attackVector,
    SecurityContext? securityContext,
  }) {
    final message =
        'Identity Spoofing: payload claims org=$payloadOrgId '
        'but JWT says org=$jwtOrgId (session: $sessionId)';

    if (kDebugMode) {
      debugPrint('[FORENSIC SECURITY] $message');
    }

    if (!EnvironmentConfig.sentryEnabled) return;

    Sentry.configureScope((scope) {
      scope.level = SentryLevel.error;
      _applyTags(
        scope,
        securityEvent: 'IDENTITY_SPOOFING',
        severity: 'CRITICAL',
        requesterOrgId: jwtOrgId,
        resourceOwnerOrgId: payloadOrgId,
        attackVector: attackVector,
        securityContext: securityContext,
      );
      _applyContext(
        scope,
        resourceType: 'session',
        resourceId: sessionId,
        attackVector: attackVector,
        securityContext: securityContext,
      );
      scope.setContexts('forensic_data', {
        'payload_org_id': payloadOrgId,
        'jwt_org_id': jwtOrgId,
        'session_id': sessionId,
      });
    });
    Sentry.captureMessage(message);
  }

  // ── Internal Helpers ──────────────────────────────────────────────────

  static void _applyTags(
    Scope scope, {
    required String securityEvent,
    required String severity,
    String? requesterOrgId,
    String? resourceOwnerOrgId,
    String? attackVector,
    SecurityContext? securityContext,
  }) {
    scope.setTag('security_event', securityEvent);
    scope.setTag('severity', severity);
    if (requesterOrgId != null) {
      scope.setTag('requester_org', requesterOrgId);
    }
    if (resourceOwnerOrgId != null) {
      scope.setTag('resource_owner_org', resourceOwnerOrgId);
    }
    if (attackVector != null) {
      scope.setTag('attack_vector', attackVector);
    }

    // Inject SecurityContext tags (SOC correlation)
    if (securityContext != null) {
      for (final entry in securityContext.toSentryTags().entries) {
        scope.setTag(entry.key, entry.value);
      }
    }
  }

  static void _applyContext(
    Scope scope, {
    required String resourceType,
    required String resourceId,
    String? attackVector,
    SecurityContext? securityContext,
  }) {
    final contextData = <String, String?>{
      'resource_type': resourceType,
      'resource_id': resourceId,
      'attack_vector': attackVector,
    };

    // Merge SecurityContext into forensic context
    if (securityContext != null) {
      contextData.addAll(securityContext.toSentryContext());
    }

    scope.setContexts('forensic_event', contextData);
  }
}
