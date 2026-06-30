import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'helpers/sla_template_robot.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(PenaltiesFormData.defaults());
    registerFallbackValue(TransportVertical.custom);
    registerFallbackValue(DateTime.utc(2024));
  });

  group('9. Passo 1 — Identidade', () {
    late MockSaveHandler handler;

    setUp(() {
      handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler);
    });

    // ── 9.1 Validação ───────────────────────────────────────────────────────

    group('9.1 Validação — integridade do campo Nome', () {
      testWidgets('nome só com espaços → "Obrigatório" (trim enforced)', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        await tester.enterText(find.byType(TextFormField).first, '   ');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsOneWidget);
        expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
      });

      testWidgets('nome com 1 caractere → válido, avança para Step2', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        await tester.enterText(find.byType(TextFormField).first, 'X');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Obrigatório'), findsNothing);
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });

      testWidgets('erro desaparece após corrigir nome e tentar novamente', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        await tester.tap(find.text('Próximo'));
        await tester.pump();
        expect(find.text('Obrigatório'), findsOneWidget);

        await tester.enterText(
          find.byType(TextFormField).first,
          'Nome Correto',
        );
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Obrigatório'), findsNothing);
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 9.2 Smart Defaults — verticais não cobertas nos grupos anteriores ───

    group('9.2 Smart Defaults — Fretamento, CargaRefrigerada, Transferência', () {
      testWidgets(
        'Fretamento → noShowMult = "2.0" (distinto do default inicial "1.5")',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();

          await robot.selectVertical(TransportVertical.fretamento);
          await robot.fillStep1(name: 'Modelo Fretamento');
          await robot.tapNext(); // Step 2
          await robot.tapNext(); // Step 3

          // Step3: Penalidade/min(0), Downgrade(1), Multiplicador No-Show(2)
          final noShowMultField = tester.widget<TextFormField>(
            find.byType(TextFormField).at(2),
          );
          expect(noShowMultField.controller?.text, '2.0');
        },
      );

      testWidgets('CargaRefrigerada → delayTol = "10", noShowThresh = "45"', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        await robot.selectVertical(TransportVertical.cargaRefrigerada);
        await robot.fillStep1(name: 'Modelo Refrigerado');
        await robot.tapNext();

        final delayTolField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(delayTolField.controller?.text, '10');

        final noShowThreshField = tester.widget<TextFormField>(
          find.byType(TextFormField).at(1),
        );
        expect(noShowThreshField.controller?.text, '45');
      });

      testWidgets(
        'TransferenciaFuncionarios → delayTol = "10", noShowThresh = "30"',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();

          await robot.selectVertical(
            TransportVertical.transferenciaFuncionarios,
          );
          await robot.fillStep1(name: 'Modelo Transferência');
          await robot.tapNext();

          final delayTolField = tester.widget<TextFormField>(
            find.byType(TextFormField).first,
          );
          expect(delayTolField.controller?.text, '10');

          final noShowThreshField = tester.widget<TextFormField>(
            find.byType(TextFormField).at(1),
          );
          expect(noShowThreshField.controller?.text, '30');
        },
      );

      testWidgets(
        'trocar Fretamento → Escolar reaplica defaults do Escolar (delayTol = "5")',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();

          await robot.selectVertical(TransportVertical.fretamento);
          await robot.selectVertical(TransportVertical.escolar);

          await robot.fillStep1(name: 'Modelo Escola');
          await robot.tapNext();

          final delayTolField = tester.widget<TextFormField>(
            find.byType(TextFormField).first,
          );
          expect(delayTolField.controller?.text, '5');
        },
      );
    });

    // ── 9.3 Navegação ───────────────────────────────────────────────────────

    group('9.3 Navegação — estrutura e fluxo do Step 1', () {
      testWidgets('Step1 renderiza 2 TextFormFields e 1 dropdown de Vertical', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(
          find.byType(DropdownButtonFormField<TransportVertical>),
          findsOneWidget,
        );
      });

      testWidgets('label "Nome do Modelo *" visível no Step1', (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        expect(find.text('Nome do Modelo *'), findsOneWidget);
      });

      testWidgets('label "Vertical" visível no Step1', (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        expect(find.text('Vertical'), findsOneWidget);
      });

      testWidgets('nome + descrição preenchidos → avança para Step2', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.first, 'Modelo Com Desc');
        await tester.enterText(fields.last, 'Descrição longa do modelo');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 9.4 Confidencialidade — Edit Mode ───────────────────────────────────

    group('9.4 Confidencialidade — pré-carga modo edição (INV-1)', () {
      late SlaTemplateView existing;

      setUp(() {
        existing = SlaTemplateRobot.buildExistingView();
      });

      testWidgets('vertical fretamento pré-selecionada no dropdown (INV-1)', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard(existing: existing);

        expect(find.text(TransportVertical.fretamento.label), findsOneWidget);
      });

      testWidgets('descrição existente pré-preenchida no campo Descrição', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard(existing: existing);

        final descField = tester.widget<TextFormField>(
          find.byType(TextFormField).last,
        );
        expect(descField.controller?.text, 'Desc existente');
      });

      testWidgets('ID técnico do template NÃO é renderizado na tela (INV-1)', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard(existing: existing);

        expect(find.text(existing.id), findsNothing);
      });

      testWidgets('campo nome editável após pré-carga', (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard(existing: existing);

        await tester.enterText(
          find.byType(TextFormField).first,
          'Nome Atualizado',
        );
        await tester.pump();

        final nameField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(nameField.controller?.text, 'Nome Atualizado');
      });
    });
  });
}
