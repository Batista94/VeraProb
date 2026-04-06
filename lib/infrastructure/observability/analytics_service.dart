/// veraprob Analytics Service — 8.4 Observabilidade
///
/// Thin wrapper around PostHog. Lives in Infrastructure layer — never import
/// this from Domain. Domain knows nothing about analytics (INV-4).
///
/// Enabled only in staging and production (see [EnvironmentConfig.posthogEnabled]).
/// In dev: events are logged to console but NOT sent to PostHog.
library;

import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:veraprob/core/config/environment.dart';

@JS('initPosthog')
external void _jsInitPosthog(
  JSString apiKey,
  JSString apiHost,
  JSBoolean enableSessionReplay,
);

/// Product analytics events tracked by VeraProb.
abstract final class VeraProbEvent {
  // Auth
  static const String userLoggedIn = 'user_logged_in';
  static const String userLoggedOut = 'user_logged_out';

  // Contracts
  static const String contractCreated = 'contract_created';
  static const String contractSubmittedForApproval =
      'contract_submitted_for_approval';
  static const String contractApproved = 'contract_approved';
  static const String contractRejected = 'contract_rejected';

  // SLA / Engine
  static const String slaViolationGenerated = 'sla_violation_generated';
  static const String compensatingEntryCreated = 'compensating_entry_created';

  // Exports
  static const String auditPackageExported = 'audit_package_exported';

  // OCC
  static const String occDashboardOpened = 'occ_dashboard_opened';
}

/// Interface for product analytics — call [AnalyticsService.track] anywhere.
class AnalyticsService {
  AnalyticsService._();

  /// Initialize PostHog via dynamic JS injection.
  static Future<void> initialize() async {
    if (!EnvironmentConfig.posthogEnabled) {
      if (kDebugMode) {
        debugPrint(
          '[Analytics] PostHog disabled in ${EnvironmentConfig.label}',
        );
      }
      return;
    }

    if (EnvironmentConfig.posthogKey.isEmpty) {
      debugPrint('[Analytics] ⚠️ POSTHOG_KEY not set — analytics disabled.');
      return;
    }

    if (kIsWeb) {
      // Modern JS Interop (8.4 Hardening)
      _jsInitPosthog(
        EnvironmentConfig.posthogKey.toJS,
        EnvironmentConfig.posthogHost.toJS,
        EnvironmentConfig.isProd.toJS, // Session Replay only in PROD
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[Analytics] PostHog initialized (${EnvironmentConfig.label})',
      );
    }
  }

  /// Track a product analytics event with automatic 'env' tagging.
  static Future<void> track(
    String event, {
    Map<String, Object>? properties,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[Analytics] event: $event${properties != null ? ' | $properties' : ''}',
      );
    }

    if (!EnvironmentConfig.posthogEnabled ||
        EnvironmentConfig.posthogKey.isEmpty) {
      return;
    }

    // Auto-inject environment tag based on EnvironmentConfig.label
    final mergedProperties = {'env': EnvironmentConfig.label, ...?properties};

    await Posthog().capture(eventName: event, properties: mergedProperties);
  }

  /// Identify the current user session (tenant-scoped, no PII).
  static Future<void> identifyOrganization(String organizationId) async {
    if (!EnvironmentConfig.posthogEnabled ||
        EnvironmentConfig.posthogKey.isEmpty) {
      return;
    }

    await Posthog().identify(
      userId: organizationId,
      userProperties: {'env': EnvironmentConfig.label},
    );
  }

  /// Reset identity on logout.
  static Future<void> reset() async {
    if (!EnvironmentConfig.posthogEnabled ||
        EnvironmentConfig.posthogKey.isEmpty) {
      return;
    }
    await Posthog().reset();
  }
}
