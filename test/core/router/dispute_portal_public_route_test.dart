import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/features/dispute_portal/presentation/dispute_portal_page.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

/// Anon carrier gateway stub — returns an applied snapshot so the page renders
/// its De Acordo branch without any Supabase/network dependency.
class _FakeGateway implements PortalDisputeGateway {
  @override
  Future<PortalSnapshot> read(String token) async => PortalSnapshot(
    status: 'disputed',
    disputedAtUtc: null,
    resolutionDueAtUtc: null,
    ruleType: 'MAX_TOLERANCE_DELAY',
    description: 'Atraso além da tolerância',
    evidence: const [],
    snapshotHash: 'a' * 64,
    closedInternally: false,
  );

  @override
  Future<void> acknowledge({
    required String token,
    required String snapshotHash,
  }) async {}

  @override
  Future<InfractionContextProjection> readInfractionContext(
    String token,
  ) async => InfractionContextProjection(
    assetIdentifier: 'ABC-1234',
    penaltyValueCents: 15000,
    occurredAtUtc: DateTime.now().toUtc(),
    locationLabel: 'São Paulo, SP',
    recordId: 'rec-123',
    orgDisplayName: 'Transportadora ABC',
    orgCnpj: '12.345.678/0001-99',
    orgLogoUrl: '',
  );

  @override
  Future<PortalSubmissionOutcome> submitEvidence({
    required String token,
    required String justification,
    StagedFile? file,
    required String? sha256Client,
  }) async => PortalSubmissionOutcome.pendingAudit;
}

/// Minimal router mirroring the production redirect contract: an unauthenticated
/// caller is bounced to login on protected paths, but [AppRoutes.publicPaths]
/// (which includes the dispute portal deep link) is always reachable.
GoRouter _router({required bool hasSession}) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    redirect: (context, state) {
      final isPublic = AppRoutes.publicPaths.contains(state.uri.path);
      if (!hasSession && !isPublic) return AppRoutes.login;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const Scaffold(body: Text('LOGIN')),
      ),
      GoRoute(
        path: AppRoutes.disputePortal,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];
          if (token == null) return const Scaffold(body: Text('LOGIN'));
          return DisputePortalPage(token: token);
        },
      ),
    ],
  );
}

void main() {
  testWidgets('dispute portal deep link resolves anonymously (no redirect)', (
    tester,
  ) async {
    final router = _router(hasSession: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portalDisputeGatewayProvider.overrideWithValue(_FakeGateway()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('${AppRoutes.disputePortal}?token=tok-123');
    await tester.pumpAndSettle();

    // Reached the portal, NOT bounced to login.
    expect(find.text('LOGIN'), findsNothing);
    expect(find.byType(DisputePortalPage), findsOneWidget);
    expect(find.text('De Acordo — Aceitar'), findsOneWidget);
  });

  test('disputePortal is registered as a public (anon) path', () {
    expect(AppRoutes.publicPaths.contains(AppRoutes.disputePortal), isTrue);
  });
}
