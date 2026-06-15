import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/features/dispute_portal/presentation/dispute_portal_page.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

const _t = '11111111-1111-1111-1111-111111111111';
const _token = _t;

PortalSnapshot _snapshot({
  required String status,
  List<PortalEvidenceItem> evidence = const [],
}) {
  return PortalSnapshot(
    status: status,
    disputedAtUtc: DateTime.utc(2026, 6, 1),
    resolutionDueAtUtc: DateTime.utc(2026, 6, 8),
    ruleType: 'Atraso de Coleta',
    description: 'SLA de coleta excedido em 35 minutos.',
    evidence: evidence,
    snapshotHash: 'a' * 64,
  );
}

PortalEvidenceItem _evidence() => PortalEvidenceItem(
  id: 'ev-1',
  fileName: 'comprovante.pdf',
  mimeType: 'application/pdf',
  fileSizeBytes: 2048,
  sha256Hash: 'b' * 64,
  verificationStatus: 'VERIFIED',
  attachedAtUtc: DateTime.utc(2026, 6, 2),
);

/// In-memory gateway: no Supabase, no edge functions. Records the acknowledge
/// call so the test can assert the hash binding the page echoes back (INV-9).
class _FakeGateway implements PortalDisputeGateway {
  final PortalSnapshot? snapshot;
  final Object? readError;
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
    acknowledgedHash = snapshotHash;
  }

  @override
  Future<PortalSubmissionOutcome> submitEvidence({
    required String token,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    return PortalSubmissionOutcome.pendingAudit;
  }
}

Widget _host(_FakeGateway gateway) {
  return ProviderScope(
    overrides: [portalDisputeGatewayProvider.overrideWithValue(gateway)],
    child: const MaterialApp(home: DisputePortalPage(token: _token)),
  );
}

void main() {
  group('DisputePortalPage — public tokenized portal (no auth)', () {
    testWidgets('invalid token surfaces a domain message, not a stack trace', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _FakeGateway(
            readError: const PortalDisputeException(
              'Link inválido ou expirado.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Link Inválido'), findsOneWidget);
      expect(find.text('Link inválido ou expirado.'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('unexpected error degrades to a generic invalid-link card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_FakeGateway(readError: StateError('boom'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Link Inválido'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('disputed snapshot renders verdict, evidence + submit branch', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _FakeGateway(
            snapshot: _snapshot(status: 'disputed', evidence: [_evidence()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Portal de Disputa'), findsOneWidget);
      expect(find.text('Atraso de Coleta'), findsOneWidget);
      expect(find.text('Evidências (1)'), findsOneWidget);
      expect(find.text('comprovante.pdf'), findsOneWidget);
      // Disputed → counter-evidence submission offered, De Acordo hidden.
      expect(find.text('Contestar — enviar contraprova'), findsOneWidget);
      expect(find.text('De Acordo — aceitar penalidade'), findsNothing);
    });

    testWidgets('applied snapshot renders De Acordo branch with sealed hash', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_FakeGateway(snapshot: _snapshot(status: 'applied'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('De Acordo — aceitar penalidade'), findsOneWidget);
      expect(
        find.textContaining('Hash do registro: ${'a' * 64}'),
        findsOneWidget,
      );
      expect(find.text('Nenhuma evidência anexada.'), findsOneWidget);
      expect(find.text('Contestar — enviar contraprova'), findsNothing);
    });

    testWidgets(
      'confirming De Acordo echoes the sealed hash and shows receipt',
      (tester) async {
        final gateway = _FakeGateway(snapshot: _snapshot(status: 'applied'));
        await tester.pumpWidget(_host(gateway));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Confirmar De Acordo'));
        await tester.pumpAndSettle();

        // Hash binding: the page acknowledges the exact snapshot it was served.
        expect(gateway.acknowledgedHash, 'a' * 64);
        expect(find.text('Penalidade Aceita'), findsOneWidget);
        expect(find.text('De Acordo — aceitar penalidade'), findsNothing);
      },
    );
  });
}
