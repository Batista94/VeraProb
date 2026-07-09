import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/app/routing/legal_gate_redirect.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart';
import 'package:veraprob/domain/legal/legal_document.dart';

/// Tests the **production** [legalGateRedirect] SSOT (not a copy).
/// Happy path, adverse, and security (bypass / anti-loop) scenarios.

LegalDocument get _doc => LegalDocument(
  id: 'doc-1',
  docType: 'terms_of_use',
  version: '1.0',
  title: 'Termos',
  bodyMarkdown: 'body',
  contentSha256: 'a' * 64,
  publishedAtUtc: DateTime.utc(2026, 1, 1),
);

LegalConsentStatus get _pending =>
    LegalConsentStatus(state: LegalConsentState.pending, document: _doc);

const _current = LegalConsentStatus(state: LegalConsentState.current);

void main() {
  group('legalGateRedirect — happy path', () {
    test('pending consent ejects from admin dashboard', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.adminDashboard,
          consent: _pending,
        ),
        AppRoutes.legalConsent,
      );
    });

    test('pending consent ejects from nested hub route', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: '/admin/hub/drivers',
          consent: _pending,
        ),
        AppRoutes.legalConsent,
      );
    });

    test('accepted consent on gate bounces to admin dashboard', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.legalConsent,
          consent: _current,
        ),
        AppRoutes.adminDashboard,
      );
    });

    test('accepted consent on dashboard proceeds (null)', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.adminDashboard,
          consent: _current,
        ),
        isNull,
      );
    });

    test('pending user already on gate stays (no redirect loop)', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.legalConsent,
          consent: _pending,
        ),
        isNull,
      );
    });
    test('pending consent ejects from admin hub root', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.adminHub,
          consent: _pending,
        ),
        AppRoutes.legalConsent,
      );
    });

    test('version-bump pending (priorVersion set) still ejects', () {
      final reGate = LegalConsentStatus(
        state: LegalConsentState.pending,
        document: _doc,
        priorVersion: '1.0',
      );
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.adminDashboard,
          consent: reGate,
        ),
        AppRoutes.legalConsent,
      );
    });
  });

  group('legalGateRedirect — adverse / security', () {
    test('no session never redirects to legal gate', () {
      expect(
        legalGateRedirect(
          hasSession: false,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.adminDashboard,
          consent: _pending,
        ),
        isNull,
      );
    });

    test('login path never redirected even when pending', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.login,
          consent: _pending,
        ),
        isNull,
      );
    });

    test('loading consent (null) does not eject (no flicker loop)', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.adminDashboard,
          consent: null,
        ),
        isNull,
      );
    });

    test('SuperAdmin bypasses pending consent on protected routes', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: true,
          skipLgpd: false,
          path: AppRoutes.adminDashboard,
          consent: _pending,
        ),
        isNull,
      );
    });

    test('SuperAdmin on legal-consent bounces to tenants (staff path)', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: true,
          skipLgpd: false,
          path: AppRoutes.legalConsent,
          consent: _pending,
        ),
        AppRoutes.superAdminTenants,
      );
    });

    test('SKIP_LGPD_CONSENT_DEV bypass only when flag true', () {
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: true,
          path: AppRoutes.adminDashboard,
          consent: _pending,
        ),
        isNull,
      );
      // Flag false must still eject — proves bypass is not unconditional.
      expect(
        legalGateRedirect(
          hasSession: true,
          isSuperAdmin: false,
          skipLgpd: false,
          path: AppRoutes.adminDashboard,
          consent: _pending,
        ),
        AppRoutes.legalConsent,
      );
    });
  });

  testWidgets('GoRouter applies production legalGateRedirect eject', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.adminDashboard,
      redirect: (context, state) => legalGateRedirect(
        hasSession: true,
        isSuperAdmin: false,
        skipLgpd: false,
        path: state.uri.path,
        consent: _pending,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.adminDashboard,
          builder: (_, _) => const Text('dashboard'),
        ),
        GoRoute(
          path: AppRoutes.legalConsent,
          builder: (_, _) => const Text('legal-gate'),
        ),
        GoRoute(
          path: '/admin/hub/drivers',
          builder: (_, _) => const Text('drivers'),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('legal-gate'), findsOneWidget);
    expect(find.text('dashboard'), findsNothing);

    // Deep-link attempt while pending must also eject.
    router.go('/admin/hub/drivers');
    await tester.pumpAndSettle();
    expect(find.text('legal-gate'), findsOneWidget);
    expect(find.text('drivers'), findsNothing);
  });

  testWidgets('accepted user cannot remain on legal-consent', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.legalConsent,
      redirect: (context, state) => legalGateRedirect(
        hasSession: true,
        isSuperAdmin: false,
        skipLgpd: false,
        path: state.uri.path,
        consent: _current,
      ),
      routes: [
        GoRoute(
          path: AppRoutes.adminDashboard,
          builder: (_, _) => const Text('dashboard'),
        ),
        GoRoute(
          path: AppRoutes.legalConsent,
          builder: (_, _) => const Text('legal-gate'),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('dashboard'), findsOneWidget);
    expect(find.text('legal-gate'), findsNothing);
  });
}
