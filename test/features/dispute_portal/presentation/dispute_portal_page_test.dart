import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/features/dispute_portal/presentation/dispute_portal_page.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';
import 'package:veraprob/testing/fakes/fake_file_hasher.dart';

const _t = '11111111-1111-1111-1111-111111111111';
const _token = _t;

PortalSnapshot _snapshot({required String status}) {
  return PortalSnapshot(
    status: status,
    disputedAtUtc: DateTime.utc(2026, 6, 1),
    resolutionDueAtUtc: DateTime.utc(2026, 6, 8),
    ruleType: 'Atraso de Coleta',
    description: 'SLA de coleta excedido em 35 minutos.',
    evidence: const [],
    snapshotHash: 'a' * 64,
  );
}

InfractionContextProjection _context() {
  return InfractionContextProjection(
    assetIdentifier: 'ABC-1234',
    penaltyValueCents: 15000,
    measuredValue: 35,
    thresholdValue: 15,
    exceededBy: 20,
    occurredAtUtc: DateTime.utc(2026, 6, 1, 12, 0),
    locationLabel: 'CD São Paulo',
    recordId: 'REC-XYZ-789',
    orgDisplayName: 'Acme Transportes',
    orgCnpj: '00.000.000/0001-00',
    orgLogoUrl: '',
  );
}

class _FakeGateway implements PortalDisputeGateway {
  final Object? readError;
  final PortalDisputeException? submitError;
  String? acknowledgedHash;
  int submitCalls = 0;

  _FakeGateway({this.readError, this.submitError});

  @override
  Future<PortalSnapshot> read(String token) async {
    if (readError != null) throw readError!;
    return _snapshot(status: 'disputed');
  }

  @override
  Future<InfractionContextProjection> readInfractionContext(
    String token,
  ) async {
    if (readError != null) throw readError!;
    return _context();
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
    required String justification,
    StagedFile? file,
    required String? sha256Client,
  }) async {
    submitCalls++;
    if (submitError != null) throw submitError!;
    // Simulate network delay
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return PortalSubmissionOutcome.pendingAudit;
  }
}

Widget _host(_FakeGateway gateway, {FakeFileHasher? hasher}) {
  return ProviderScope(
    overrides: [
      portalDisputeGatewayProvider.overrideWithValue(gateway),
      if (hasher != null) fileHasherProvider.overrideWithValue(hasher),
    ],
    child: const MaterialApp(home: DisputePortalPage(token: _token)),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  group('DisputePortalPage — UI Tests (W1-W12)', () {
    testWidgets('W1, W2, W3: Justificativa habilita o Enviar Contestação', (
      tester,
    ) async {
      final gateway = _FakeGateway();
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();

      // W1: Initial → botão desabilitado
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Enviar Contestação'),
            )
            .enabled,
        false,
      );

      // W2: Justificativa <20 chars → permanece desabilitado
      await tester.enterText(find.byType(TextFormField), 'curta');
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Enviar Contestação'),
            )
            .enabled,
        false,
      );

      // W3: Justificativa >= 20 chars → habilitado
      await tester.enterText(
        find.byType(TextFormField),
        'Esta é uma justificativa longa o suficiente.',
      );
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Enviar Contestação'),
            )
            .enabled,
        true,
      );
    });

    testWidgets('W6: Falha de rede reflete na UI preservando estado', (
      tester,
    ) async {
      final gateway = _FakeGateway(
        submitError: const PortalDisputeException(
          'Erro de conexão ao servidor.',
        ),
      );
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        'Justificativa muito muito longa para passar de vinte.',
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Enviar Contestação'));
      await tester.tap(find.text('Enviar Contestação'));
      await tester.pump(); // trigger submit
      await tester.pumpAndSettle(); // wait for error

      // Error is displayed inline without stack traces
      expect(find.text('Erro de conexão ao servidor.'), findsOneWidget);
      // Justification is preserved
      expect(
        find.text('Justificativa muito muito longa para passar de vinte.'),
        findsOneWidget,
      );
    });

    testWidgets('W7: Duplo clique impossível', (tester) async {
      final gateway = _FakeGateway();
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        'Justificativa muito muito longa para passar de vinte.',
      );
      await tester.pump();

      // Tap twice quickly
      await tester.ensureVisible(find.text('Enviar Contestação'));
      await tester.tap(find.text('Enviar Contestação'));
      await tester.tap(find.text('Enviar Contestação'));
      await tester.pumpAndSettle(); // wait for submit completion

      expect(gateway.submitCalls, 1);
    });

    testWidgets('W8: Sucesso exibe recibo verde e oculta form', (tester) async {
      final gateway = _FakeGateway();
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        'Justificativa muito muito longa para passar de vinte.',
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Enviar Contestação'));
      await tester.tap(find.text('Enviar Contestação'));
      await tester.pumpAndSettle();

      expect(find.text('Contestação Recebida com Sucesso'), findsOneWidget);
      expect(find.text('Enviar Contestação'), findsNothing); // Form oculto
    });

    testWidgets('W10: De Acordo separado com confirmação', (tester) async {
      final gateway = _FakeGateway();
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('De Acordo — Aceitar'));
      await tester.tap(find.text('De Acordo — Aceitar'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar Aceite'), findsOneWidget);

      await tester.tap(find.text('Aceitar Infração'));
      await tester.pumpAndSettle();

      expect(gateway.acknowledgedHash, 'a' * 64);
    });

    testWidgets('W11: DisputeContextCard renderiza dados formatados', (
      tester,
    ) async {
      final gateway = _FakeGateway();
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();

      expect(find.text('DADOS IMUTÁVEIS'), findsOneWidget);
      expect(find.text('R\$ 150,00'), findsOneWidget);
      expect(find.text('ABC-1234'), findsOneWidget);
      expect(find.text('+20'), findsOneWidget);
      expect(find.text('REC-XYZ-789'), findsOneWidget);
    });

    testWidgets('invalid token surfaces a domain message', (tester) async {
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
    });
  });
}
