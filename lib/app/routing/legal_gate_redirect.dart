import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';

/// Pure LGPD Legal Gate redirect decision (defense-in-depth).
///
/// Shared by [appRouterProvider] and unit tests so regressions hit the real
/// contract — not a duplicated copy. Primary async gate remains
/// `AdminLockScreen._routeAfterAuth`; this is the sync GoRouter branch.
///
/// Returns a redirect path, or `null` to proceed.
///
/// Rules:
/// - No session / skip flag / login path → proceed
/// - SuperAdmin on `/legal-consent` → bounce to tenants (staff bypass)
/// - SuperAdmin elsewhere → proceed
/// - Consent still loading (`null`) → proceed (eject after resolve)
/// - Pending + not already on gate → `/legal-consent`
/// - Current + on gate → admin dashboard
String? legalGateRedirect({
  required bool hasSession,
  required bool isSuperAdmin,
  required bool skipLgpd,
  required String path,
  required LegalConsentStatus? consent,
}) {
  if (!hasSession) return null;
  if (skipLgpd) return null;
  if (path == AppRoutes.login) return null;

  if (isSuperAdmin) {
    if (path == AppRoutes.legalConsent) return AppRoutes.superAdminTenants;
    return null;
  }

  if (consent == null) return null;
  if (consent.isPending && path != AppRoutes.legalConsent) {
    return AppRoutes.legalConsent;
  }
  if (consent.isCurrent && path == AppRoutes.legalConsent) {
    return AppRoutes.adminDashboard;
  }
  return null;
}
