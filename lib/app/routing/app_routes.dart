import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';

/// Canonical URL path constants for the application router.
///
/// Single source of truth for every navigable location. Presentation code
/// MUST reference these constants (or [AdminNavRoute.path]) instead of string
/// literals so that renaming a route stays atomic across the codebase.
sealed class AppRoutes {
  // ── Public (no authenticated session required) ────────────
  static const String login = '/login';
  static const String acceptInvite = '/accept-invite';
  static const String reviewContract = '/review-contract';
  static const String justify = '/justify';

  /// Tokenized dispute portal for external carriers (no session). Token is a
  /// `?token=` query param so the static path stays in [publicPaths].
  static const String disputePortal = '/portal/dispute';

  // ── Admin shell ───────────────────────────────────────────
  static const String adminDashboard = '/admin/dashboard';
  static const String adminHub = '/admin/hub';

  // ── Super-admin ───────────────────────────────────────────
  static const String superAdmin = '/super-admin';
  static const String superAdminMfaEnrollment = '/super-admin/mfa-enrollment';
  static const String superAdminMfaChallenge = '/super-admin/mfa-challenge';
  static const String superAdminTenants = '/super-admin/tenants';
  static const String superAdminNewOrg = '/super-admin/new-org';
  static const String superAdminAuditLog = '/super-admin/audit-log';

  /// Tenant detail deep link. `:id` is a tenant UUID.
  static const String superAdminTenantDetailPattern =
      '/super-admin/tenants/:id';

  static String superAdminTenantDetail(String tenantId) =>
      '/super-admin/tenants/$tenantId';

  /// Rule Studio for a contract. Nested under the contracts admin branch so the
  /// shell + sidebar selection are preserved. `:contractId` is a contract UUID.
  static String contractRules(String contractId) =>
      '/admin/hub/contracts/$contractId/rules';

  /// Fleet Risk analytics dashboard (carrier ranking + risk thermometer).
  /// Nested under the Administração hub branch so the shell is preserved.
  static const String fleetRiskAnalytics = '/admin/hub/fleet-risk';

  /// Ingestion Health Monitor dashboard.
  /// Nested under the Administração hub branch so the shell is preserved.
  static const String ingestionHealth = '/admin/hub/ingestion-health';

  /// Deep link to a specific vehicle's health detail (drill-down from alerts).
  static String ingestionHealthVehicle(String vehicleId) =>
      '/admin/hub/ingestion-health?vehicleId=$vehicleId';

  /// Webhooks integration management.
  static const String webhooks = '/admin/hub/webhooks';

  /// Routes reachable without an authenticated session. The router redirect
  /// guard bounces every other path to [login] when there is no session.
  static const Set<String> publicPaths = {
    login,
    acceptInvite,
    reviewContract,
    justify,
    disputePortal,
  };
}

/// Bidirectional mapping between an [AdminNav] destination and its URL path.
///
/// The first [pillarCount] destinations are the sidebar pillars and live
/// directly under `/admin`; the remaining hub destinations live under
/// `/admin/hub`. Branch order in the admin `StatefulShellRoute` MUST match
/// [AdminNav] declaration order so that `currentIndex == AdminNav.x.index`.
extension AdminNavRoute on AdminNav {
  String get path => switch (this) {
    AdminNav.dashboard => AppRoutes.adminDashboard,
    AdminNav.auditorQueue => '/admin/auditor-queue',
    AdminNav.defensePortal => '/admin/defense-portal',
    AdminNav.financialImpact => '/admin/financial-impact',
    AdminNav.operationalAudit => '/admin/operational-audit',
    AdminNav.adminHub => AppRoutes.adminHub,
    AdminNav.drivers => '/admin/hub/drivers',
    AdminNav.timecards => '/admin/hub/timecards',
    AdminNav.contracts => '/admin/hub/contracts',
    AdminNav.slaAudit => '/admin/hub/sla-audit',
    AdminNav.zones => '/admin/hub/zones',
    AdminNav.billingReports => '/admin/hub/billing-reports',
    AdminNav.slaTemplates => '/admin/hub/sla-templates',
    AdminNav.orgSettings => '/admin/hub/org-settings',
    AdminNav.userManagement => '/admin/hub/user-management',
    AdminNav.contractors => '/admin/hub/contractors',
    AdminNav.settings => '/admin/hub/settings',
    AdminNav.evidence => '/admin/hub/evidence',
    AdminNav.webhooks => AppRoutes.webhooks,
  };

  /// Resolves a URL path back to its [AdminNav], or `null` when the path is
  /// not an admin destination.
  static AdminNav? fromPath(String path) {
    for (final nav in AdminNav.values) {
      if (nav.path == path) return nav;
    }
    return null;
  }
}
