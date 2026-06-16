import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/features/dispute_portal/presentation/dispute_portal_page.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

class _FakeGateway implements PortalDisputeGateway {
  final PortalSnapshot? snapshot;
  final Object? readError;
  int acknowledgeCount = 0;
  String? acknowledgedHash;

  _FakeGateway({this.snapshot, this.readError});

  @override
  Future<PortalSnapshot> read(String token) async {
    if (readError != null) throw readError!;
    return snapshot!;
  }

  @override
  Future<void> acknowledge({
    required String token,
    required String snapshotHash,
  }) async {
    acknowledgeCount++;
    acknowledgedHash = snapshotHash;
  }

  @override
  Future<InfractionContextProjection> readInfractionContext(
    String token,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PortalSubmissionOutcome> submitEvidence({
    required String token,
    required String justification,
    StagedFile? file,
    required String? sha256Client,
  }) async => PortalSubmissionOutcome.pendingAudit;
}

PortalSnapshot _snap(String status) => PortalSnapshot(
  status: status,
  disputedAtUtc: null,
  resolutionDueAtUtc: null,
  ruleType: 'MAX_TOLERANCE_DELAY',
  description: 'Atraso além da tolerância',
  evidence: const [],
  snapshotHash: 'a' * 64,
);

Future<void> _pump(WidgetTester tester, _FakeGateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [portalDisputeGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: DisputePortalPage(token: 'tok')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('applied sanction shows De Acordo branch and acknowledges', (
    tester,
  ) async {
    final gateway = _FakeGateway(snapshot: _snap('applied'));
    await _pump(tester, gateway);

    expect(find.text('De Acordo — aceitar penalidade'), findsOneWidget);
    expect(find.text('Contestar — enviar contraprova'), findsNothing);

    await tester.tap(find.text('Confirmar De Acordo'));
    await tester.pumpAndSettle();

    expect(gateway.acknowledgeCount, 1);
    expect(gateway.acknowledgedHash, 'a' * 64);
    expect(find.text('Penalidade Aceita'), findsOneWidget);
  });

  testWidgets('disputed sanction shows the counter-evidence branch', (
    tester,
  ) async {
    await _pump(tester, _FakeGateway(snapshot: _snap('disputed')));
    expect(find.text('Contestar — enviar contraprova'), findsOneWidget);
    expect(find.text('De Acordo — aceitar penalidade'), findsNothing);
  });

  testWidgets('invalid token shows the error card', (tester) async {
    await _pump(
      tester,
      _FakeGateway(
        readError: const PortalDisputeException('Link inválido ou expirado.'),
      ),
    );
    expect(find.text('Link Inválido'), findsOneWidget);
    expect(find.text('Link inválido ou expirado.'), findsOneWidget);
  });
}
