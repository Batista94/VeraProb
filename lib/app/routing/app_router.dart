import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart'
    show SentryNavigatorObserver;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/features/admin/presentation/widgets/admin_layout.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/features/admin/presentation/lock_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/accept_invite_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/driver_justification_page.dart';
import 'package:veraprob/features/admin/presentation/screens/review_contract_screen.dart';
import 'package:veraprob/features/shared/widgets/error_boundary.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

// ── Admin branch screens (order MUST match AdminNav) ──────────
import 'package:veraprob/features/admin/presentation/dashboard_screen.dart';
import 'package:veraprob/features/admin/presentation/drivers_screen.dart';
import 'package:veraprob/features/admin/presentation/timecard_reports_screen.dart';
import 'package:veraprob/features/admin/presentation/command_center/screens/operational_audit_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/contracts_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/sla_audit_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/sla_financial_impact_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/operational_zones_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/billing_cycle_reports_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/org_settings_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/user_management_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/contractor_management_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/auditor_queue_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/defense_portal_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/sla_template_library_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/admin_hub_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/evidence_reconciliation_screen.dart';
import 'package:veraprob/presentation/shell/settings_screen.dart';

// ── Super-admin shell + branch screens ──
import 'package:veraprob/features/super_admin/presentation/super_admin_shell.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_health_panel.dart';
import 'package:veraprob/features/super_admin/presentation/screens/create_organization_wizard.dart';
import 'package:veraprob/features/super_admin/presentation/screens/super_admin_audit_log_screen.dart';
import 'package:veraprob/features/super_admin/presentation/screens/mfa_enrollment_screen.dart';
import 'package:veraprob/features/super_admin/presentation/screens/mfa_challenge_screen.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Bridges Supabase auth changes into a [Listenable] that [GoRouter] can
/// observe via `refreshListenable`. Every auth event (notably
/// `AuthChangeEvent.signedOut`) re-runs the router redirect, so an expired or
/// revoked session bounces the user back to [AppRoutes.login] from any screen
/// (closes the AUTH-TRAP / NotFoundPage dead-end).
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier(Stream<AuthState> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Builds one admin shell branch: a single [GoRoute] rendering [screen] at the
/// canonical [nav] path. Branch order in [appRouterProvider] MUST match the
/// [AdminNav] declaration order so `navigationShell.currentIndex == nav.index`.
StatefulShellBranch _adminBranch(AdminNav nav, Widget screen) {
  return StatefulShellBranch(
    routes: [GoRoute(path: nav.path, builder: (context, state) => screen)],
  );
}

/// Application router (Flutter Web URL-addressable navigation).
///
/// Public surface (login + token deep links) + the admin
/// [StatefulShellRoute.indexedStack] (18 URL-addressable branches) + the
/// super-admin entry points. The post-login destination stays owned by
/// `AdminLockScreen._routeAfterAuth` (async MFA gating); the redirect guard
/// only bounces unauthenticated access on protected routes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final refresh = AuthRefreshNotifier(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.login,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refresh,
    observers: [SentryNavigatorObserver()],
    redirect: (context, state) {
      final hasSession = client.auth.currentSession != null;
      final path = state.uri.path;
      final isPublic = AppRoutes.publicPaths.contains(path);

      // Unauthenticated access to a protected route → login. Logged-in users
      // are deliberately NOT auto-forwarded off /login: the post-auth
      // destination is owned by AdminLockScreen._routeAfterAuth (async MFA
      // gating for super-admins).
      if (!hasSession && !isPublic) return AppRoutes.login;

      // The super-admin portal is a branched shell; `/super-admin` itself is not
      // a branch. Forward the legacy entry point (and any bookmark) onto the
      // first branch so `_routeAfterAuth`/deep links land on the Tenants tab.
      if (path == AppRoutes.superAdmin) return AppRoutes.superAdminTenants;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            const ErrorBoundary(child: AdminLockScreen()),
      ),
      GoRoute(
        path: AppRoutes.acceptInvite,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];
          if (token == null) return const AdminLockScreen();
          return AcceptInviteScreen(token: token);
        },
      ),
      GoRoute(
        path: AppRoutes.reviewContract,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];
          if (token == null) return const AdminLockScreen();
          return ReviewContractScreen(token: token);
        },
      ),
      GoRoute(
        path: AppRoutes.justify,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];
          if (token == null) return const AdminLockScreen();
          return DriverJustificationPage(token: token);
        },
      ),

      // ── Admin shell — URL-addressable IndexedStack (state preserved) ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdminLayout(navigationShell: navigationShell),
        branches: [
          _adminBranch(AdminNav.dashboard, const DashboardScreen()),
          _adminBranch(AdminNav.auditorQueue, const AuditorQueueScreen()),
          _adminBranch(AdminNav.defensePortal, const DefensePortalScreen()),
          _adminBranch(
            AdminNav.financialImpact,
            const SlaFinancialImpactScreen(),
          ),
          _adminBranch(
            AdminNav.operationalAudit,
            const OperationalAuditScreen(),
          ),
          _adminBranch(AdminNav.adminHub, const AdminHubScreen()),
          _adminBranch(AdminNav.drivers, const DriversScreen()),
          _adminBranch(AdminNav.timecards, const TimecardReportsScreen()),
          _adminBranch(AdminNav.contracts, const ContractsScreen()),
          _adminBranch(AdminNav.slaAudit, const SlaAuditScreen()),
          _adminBranch(AdminNav.zones, const OperationalZonesScreen()),
          _adminBranch(
            AdminNav.billingReports,
            const BillingCycleReportsScreen(),
          ),
          _adminBranch(AdminNav.slaTemplates, const SlaTemplateLibraryScreen()),
          _adminBranch(AdminNav.orgSettings, const OrgSettingsScreen()),
          _adminBranch(AdminNav.userManagement, const UserManagementScreen()),
          _adminBranch(
            AdminNav.contractors,
            const ContractorManagementScreen(),
          ),
          _adminBranch(AdminNav.settings, const SettingsScreen()),
          _adminBranch(AdminNav.evidence, const EvidenceReconciliationScreen()),
        ],
      ),

      // ── Super-admin MFA gates (standalone — outside the guarded shell) ──
      GoRoute(
        path: AppRoutes.superAdminMfaEnrollment,
        builder: (context, state) => const MfaEnrollmentScreen(),
      ),
      GoRoute(
        path: AppRoutes.superAdminMfaChallenge,
        builder: (context, state) => const MfaChallengeScreen(),
      ),

      // ── Super-admin shell — URL-addressable IndexedStack (3 branches) ──
      // Branch order MUST stay Tenants / Nova Org / Audit Log so the rail's
      // `currentIndex` matches `SuperAdminShell`'s destination order.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            SuperAdminShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.superAdminTenants,
                builder: (context, state) => const TenantHealthPanel(),
                routes: [
                  // Deep link `/super-admin/tenants/:id` → preselect the tenant.
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => _SuperAdminTenantDeepLink(
                      tenantId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.superAdminNewOrg,
                builder: (context, state) => CreateOrganizationWizard(
                  onSuccess: () => context.go(AppRoutes.superAdminTenants),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.superAdminAuditLog,
                builder: (context, state) => const SuperAdminAuditLogScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

/// Renders the Tenants branch with [tenantId] preselected.
///
/// Backs the `/super-admin/tenants/:id` deep link: it seeds
/// [selectedTenantIdProvider] after first frame (so the detail pane opens) and
/// then defers to [TenantHealthPanel], which already reconciles the selection
/// against the loaded snapshot (clearing it with a "not found" notice on a stale
/// or cross-tenant id — INV-22/INV-26).
class _SuperAdminTenantDeepLink extends ConsumerStatefulWidget {
  const _SuperAdminTenantDeepLink({required this.tenantId});

  final String tenantId;

  @override
  ConsumerState<_SuperAdminTenantDeepLink> createState() =>
      _SuperAdminTenantDeepLinkState();
}

class _SuperAdminTenantDeepLinkState
    extends ConsumerState<_SuperAdminTenantDeepLink> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedTenantIdProvider.notifier).select(widget.tenantId);
    });
  }

  @override
  Widget build(BuildContext context) => const TenantHealthPanel();
}
