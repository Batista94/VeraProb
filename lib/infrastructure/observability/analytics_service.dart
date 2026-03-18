/// PactaFlow Analytics Service — 8.4 Observabilidade
///
/// Thin wrapper around PostHog. Lives in Infrastructure layer — never import
/// this from Domain. Domain knows nothing about analytics (INV-4).
///
/// Enabled only in staging and production (see [EnvironmentConfig.posthogEnabled]).
/// In dev: events are logged to console but NOT sent to PostHog.
library;

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import '../../core/config/environment.dart';

/// Product analytics events tracked by PactaFlow.
/// Centralizing event names prevents typos and enables refactoring safety.
abstract final class PactaFlowEvent {
  // Auth
  static const String userLoggedIn = 'user_logged_in';
  static const String userLoggedOut = 'user_logged_out';

  // Contracts
  static const String contractCreated = 'contract_created';
  static const String contractSubmittedForApproval = 'contract_submitted_for_approval';
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

/// Interface for product analytics — call [AnalyticsService.track] anywhere
/// in the Infrastructure or Presentation layers.
///
/// NEVER log financial values or PII (CPF, email, phone) as event properties.
class AnalyticsService {
  AnalyticsService._();

  /// Initialize PostHog. Must be called during app bootstrap, before [runApp].
  static Future<void> initialize() async {
    if (!EnvironmentConfig.posthogEnabled) {
      if (kDebugMode) {
        debugPrint('[Analytics] PostHog disabled in ${EnvironmentConfig.label}');
      }
      return;
    }

    if (EnvironmentConfig.posthogKey.isEmpty) {
      debugPrint('[Analytics] ⚠️ POSTHOG_KEY not set — analytics disabled.');
      return;
    }

    // PostHog Flutter 5.x API:
    // PostHogConfig(apiKey) — fields are mutable after construction.
    final config = PostHogConfig(EnvironmentConfig.posthogKey);
    config.host = EnvironmentConfig.posthogHost;
    config.debug = kDebugMode;
    config.captureApplicationLifecycleEvents = false; // manual control
    config.sendFeatureFlagEvents = false;
    config.sessionReplay = false;            // privacy: no session recording
    config.surveys = false;                  // not needed in MVP
    config.errorTrackingConfig.captureFlutterErrors = false; // Sentry handles this

    await Posthog().setup(config);

    if (kDebugMode) {
      debugPrint('[Analytics] PostHog initialized (${EnvironmentConfig.label})');
    }
  }

  /// Track a product analytics event.
  ///
  /// [event] should be a constant from [PactaFlowEvent].
  /// [properties] must NEVER contain PII or financial amounts.
  static Future<void> track(
    String event, {
    Map<String, Object>? properties,
  }) async {
    if (kDebugMode) {
      // Always log to console in dev for visibility.
      debugPrint('[Analytics] event: $event${properties != null ? ' | $properties' : ''}');
    }

    if (!EnvironmentConfig.posthogEnabled || EnvironmentConfig.posthogKey.isEmpty) {
      return;
    }

    await Posthog().capture(
      eventName: event,
      properties: properties,
    );
  }

  /// Identify the current user session (tenant-scoped, no PII).
  ///
  /// Use [organizationId] as the distinct_id to keep analytics tenant-isolated.
  /// NEVER use email or CPF as the distinct_id.
  static Future<void> identifyOrganization(String organizationId) async {
    if (!EnvironmentConfig.posthogEnabled || EnvironmentConfig.posthogKey.isEmpty) {
      return;
    }

    await Posthog().identify(
      userId: organizationId,
      userProperties: {
        'environment': EnvironmentConfig.label,
      },
    );
  }

  /// Reset identity on logout (clears distinctId).
  static Future<void> reset() async {
    if (!EnvironmentConfig.posthogEnabled || EnvironmentConfig.posthogKey.isEmpty) {
      return;
    }
    await Posthog().reset();
  }
}
