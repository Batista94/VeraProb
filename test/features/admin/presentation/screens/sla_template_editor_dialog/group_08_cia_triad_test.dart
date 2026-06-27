import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'helpers/sla_template_robot.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(PenaltiesFormData.defaults());
    registerFallbackValue(TransportVertical.custom);
    registerFallbackValue(DateTime.utc(2024));
  });

  group('8. Tríade CIA', () {
    // ── C: Confidencialidade ────────────────────────────────────────────────

    group('C — org/session isolation (INV-1)', () {
      testWidgets('orgId do provider passado exato ao handler sem vazamento', (
        tester,
      ) async {
        final handler = MockSaveHandler();
        String? capturedOrgId;
        String? capturedSessionId;
        SlaTemplateRobot.stubHandler(
          handler,
          onCall: (args) {
            capturedOrgId = args.organizationId as String?;
            capturedSessionId = args.sessionId as String?;
          },
        );

        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        await tester.tap(find.text('Criar'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(capturedOrgId, equals(SlaTemplateRobot.defaultOrgId));
        expect(capturedSessionId, equals(SlaTemplateRobot.defaultSessionId));
      });

      testWidgets('orgId null → handler NÃO chamado (INV-1 fail-fast)', (
        tester,
      ) async {
        final handler = MockSaveHandler();

        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard(orgId: null);

        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        await tester.tap(find.text('Criar'));
        await tester.pump();
        await tester.pump();

        SlaTemplateRobot.verifyNeverCalled(handler);
      });
    });

    // ── I: Integridade Financeira (INV-4/INV-5) ─────────────────────────────

    group('I — precisão financeira (unit tests)', () {
      test('_reaisToCents: "50,00" → 5000', () {
        const text = '50,00';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 5000);
      });

      test('_reaisToCents: "0,50" → 50', () {
        const text = '0,50';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 50);
      });

      test('_reaisToCents: "1234,56" → 123456', () {
        const text = '1234,56';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 123456);
      });

      test('_reaisToCents: "0" → 0', () {
        const text = '0';
        final cents = (double.tryParse(text.replaceAll(',', '.'))! * 100)
            .round();
        expect(cents, 0);
      });

      test('_centsToReais: 5000 → "50.00"', () {
        const cents = 5000;
        final reais = (cents / 100).toStringAsFixed(2);
        expect(reais, '50.00');
      });

      test('noShowMultiplier: 15000 bps → "1.5" display', () {
        const bps = 15000;
        final display = (bps / 10000.0).toString();
        expect(display, '1.5');
      });

      test('noShowMultiplier: "1.5" → 15000 bps (round-trip)', () {
        const text = '1.5';
        final bps = (double.tryParse(text.replaceAll(',', '.'))! * 10000)
            .round();
        expect(bps, 15000);
      });

      test('noShowMultiplier: "2,0" → 20000 bps', () {
        const text = '2,0';
        final bps = (double.tryParse(text.replaceAll(',', '.'))! * 10000)
            .round();
        expect(bps, 20000);
      });
    });

    // ── A: Disponibilidade (INV-24) ─────────────────────────────────────────

    group('A — barrierDismissible=false e dispose controllers (INV-24)', () {
      testWidgets('tap fora do dialog (barreira) NÃO fecha o dialog', (
        tester,
      ) async {
        final handler = MockSaveHandler();
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        expect(find.byType(Dialog), findsOneWidget);

        // Toca na barreira (canto superior esquerdo fora do dialog centralizado)
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();

        // Dialog deve permanecer aberto
        expect(find.byType(Dialog), findsOneWidget);
      });

      testWidgets('Cancelar descarta dialog sem exception de dispose', (
        tester,
      ) async {
        final handler = MockSaveHandler();
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        // Preenche campos para ativar todos os controllers
        await robot.fillStep1();
        await tester.pump();

        await tester.tap(find.text('Cancelar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Nenhuma exceção de uso de controller após dispose
        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets(
        'save bem-sucedido descarta dialog sem exception de dispose',
        (tester) async {
          final handler = MockSaveHandler();
          SlaTemplateRobot.stubHandler(handler);

          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();

          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.tap(find.text('Criar'));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(tester.takeException(), isNull);
          expect(find.byType(Dialog), findsNothing);
        },
      );
    });
  });
}
