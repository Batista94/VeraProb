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

  group('10. Passo 2 — Temporal', () {
    late MockSaveHandler handler;

    setUp(() {
      handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler);
    });

    Future<void> tapBack(WidgetTester tester) async {
      await tester.tap(find.text('Anterior'));
      await tester
          .pumpAndSettle(); // AnimatedSwitcher must fully remove exiting child
    }

    // ── 10.1 Validação ───────────────────────────────────────────────────────

    group('10.1 Validação — inputs numéricos e campos obrigatórios', () {
      testWidgets('todos os 5 campos vazios → 5x "Obrigatório" exibidos', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext(); // goto step2

        for (int i = 0; i < 5; i++) {
          await tester.enterText(find.byType(TextFormField).at(i), '');
          await tester.pump();
        }
        await tester.tap(find.text('Próximo'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsNWidgets(5));
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });

      testWidgets('input formatter bloqueia letras — apenas dígitos aceitos', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();

        await tester.enterText(find.byType(TextFormField).first, 'abc5xyz');
        await tester.pump();

        final field = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(field.controller?.text, '5');
      });

      testWidgets(
        'input formatter bloqueia ponto decimal — campo inteiro rejeita "."',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).first, '1.5');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).first,
          );
          expect(field.controller?.text, '15');
        },
      );

      testWidgets('campo Dwell Time vazio (idx 3) → "Obrigatório"', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();

        await tester.enterText(find.byType(TextFormField).at(3), '');
        await tester.pump();
        await tester.tap(find.text('Próximo'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsOneWidget);
        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 10.2 Integridade Forense ─────────────────────────────────────────────

    group('10.2 Integridade Forense — persistência de estado ao navegar', () {
      testWidgets('valores padrão do Step2 refletem domain defaults', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();

        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(0))
              .controller
              ?.text,
          '15', // delayToleranceMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller
              ?.text,
          '60', // noShowThresholdMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(2))
              .controller
              ?.text,
          '5', // earlyArrivalToleranceMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(3))
              .controller
              ?.text,
          '3', // dwellTimeMinutes
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(4))
              .controller
              ?.text,
          '0', // gracePeriodMinutes
        );
      });

      testWidgets(
        'Step2→Step3→Anterior: todos os valores editados no Step2 persistem',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).at(0), '20');
          await tester.enterText(find.byType(TextFormField).at(1), '45');
          await tester.enterText(find.byType(TextFormField).at(2), '8');
          await tester.enterText(find.byType(TextFormField).at(3), '10');
          await tester.enterText(find.byType(TextFormField).at(4), '2');
          await tester.pump();

          await robot.tapNext(); // Step3
          await tapBack(tester); // volta Step2

          expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '20',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '45',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(2))
                .controller
                ?.text,
            '8',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(3))
                .controller
                ?.text,
            '10',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(4))
                .controller
                ?.text,
            '2',
          );
        },
      );

      testWidgets(
        'Step2→Step1(Anterior)→Step2(Próximo): estado dos controllers preservado',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).at(0), '25');
          await tester.enterText(find.byType(TextFormField).at(1), '90');
          await tester.pump();

          await tapBack(tester); // Step1
          expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);

          await robot.tapNext(); // Step2 novamente
          expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);

          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '25',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '90',
          );
        },
      );
    });

    // ── 10.3 Navegação ───────────────────────────────────────────────────────

    group('10.3 Navegação — comportamento do Step2', () {
      testWidgets(
        'Anterior NÃO dispara validação — campo vazio permite voltar',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).first, '');
          await tester.pump();

          await tapBack(tester);

          expect(find.text('Obrigatório'), findsNothing);
          expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
        },
      );

      testWidgets('Step2 renderiza exatamente 5 TextFormFields', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();

        expect(find.byType(TextFormField), findsNWidgets(5));
      });

      testWidgets('Próximo com defaults válidos avança para Step3', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();

        await robot.tapNext();

        expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
      });
    });

    // ── 10.4 Decorações ──────────────────────────────────────────────────────

    group('10.4 Decorações — sufixos e labels do Step2', () {
      testWidgets('sufixo "min" renderizado em todos os 5 campos do Step2', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();

        expect(find.text('min'), findsNWidgets(5));
      });

      testWidgets('labels corretas nos 5 campos do Step2', (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();

        expect(find.text('Tolerância Atraso'), findsOneWidget);
        expect(find.text('Limiar No-Show'), findsOneWidget);
        expect(find.text('Tolerância Antecipação'), findsOneWidget);
        expect(find.text('Dwell Time'), findsOneWidget);
        expect(find.text('Período de Graça'), findsOneWidget);
      });
    });
  });
}
