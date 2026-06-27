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

  group('11. Passo 3 — Financeiro', () {
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

    // ── 11.1 Validação ────────────────────────────────────────────────────────

    group('11.1 Validação — inputs decimais e campos obrigatórios', () {
      testWidgets('todos os 4 campos vazios → 4x "Obrigatório" exibidos', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        for (int i = 0; i < 4; i++) {
          await tester.enterText(find.byType(TextFormField).at(i), '');
          await tester.pump();
        }
        await tester.tap(find.text('Criar'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsNWidgets(4));
        expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
      });

      testWidgets(
        'formatter ACEITA vírgula — "1,50" preservado no controller',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).at(0), '1,50');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          );
          expect(field.controller?.text, '1,50');
        },
      );

      testWidgets(
        'formatter ACEITA ponto decimal — "1.50" preservado no controller',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).at(0), '1.50');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          );
          expect(field.controller?.text, '1.50');
        },
      );

      testWidgets(
        'formatter BLOQUEIA letras — "abc1,5xyz" → "1,5" no controller',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).at(0), 'abc1,5xyz');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(0),
          );
          expect(field.controller?.text, '1,5');
        },
      );

      testWidgets(
        'Multiplicador No-Show (idx 2) aceita decimal — "1.5" preservado',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).at(2), '1.5');
          await tester.pump();

          final field = tester.widget<TextFormField>(
            find.byType(TextFormField).at(2),
          );
          expect(field.controller?.text, '1.5');
        },
      );

      testWidgets('Multiplicador No-Show vazio (idx 2) → "Obrigatório"', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        await tester.enterText(find.byType(TextFormField).at(2), '');
        await tester.pump();
        await tester.tap(find.text('Criar'));
        await tester.pump();

        expect(find.text('Obrigatório'), findsOneWidget);
        expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
      });

      testWidgets(
        'todos os 4 campos usam keyboardType numberWithOptions(decimal: true)',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          // TextFormField does not expose keyboardType directly — reach the inner TextField.
          for (int i = 0; i < 4; i++) {
            final textField = tester.widget<TextField>(
              find.descendant(
                of: find.byType(TextFormField).at(i),
                matching: find.byType(TextField),
              ),
            );
            expect(
              textField.keyboardType,
              const TextInputType.numberWithOptions(decimal: true),
              reason: 'Campo $i deve usar teclado decimal',
            );
          }
        },
      );
    });

    // ── 11.2 Integridade Financeira ───────────────────────────────────────────

    group('11.2 Integridade Financeira — defaults e persistência', () {
      testWidgets('valores padrão do Step3 refletem domain defaults', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        // delayPenaltyPerMinuteCents=50 → (50/100).toStringAsFixed(2) = '0.50'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(0))
              .controller
              ?.text,
          '0.50',
        );
        // downgradePenaltyFlatCents=5000 → (5000/100).toStringAsFixed(2) = '50.00'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(1))
              .controller
              ?.text,
          '50.00',
        );
        // noShowPenaltyBps=15000 → (15000/10000.0).toString() = '1.5'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(2))
              .controller
              ?.text,
          '1.5',
        );
        // baseTripValueCents=0 → (0/100).toStringAsFixed(2) = '0.00'
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).at(3))
              .controller
              ?.text,
          '0.00',
        );
      });

      testWidgets(
        'Step3→Anterior→Step3: valores editados persistem após navegação',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.enterText(find.byType(TextFormField).at(0), '1,50');
          await tester.enterText(find.byType(TextFormField).at(1), '75,00');
          await tester.enterText(find.byType(TextFormField).at(2), '2.0');
          await tester.enterText(find.byType(TextFormField).at(3), '100,00');
          await tester.pump();

          await tapBack(tester); // Step3 → Step2
          expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);

          await robot.tapNext(); // Step2 → Step3
          expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);

          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '1,50',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '75,00',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(2))
                .controller
                ?.text,
            '2.0',
          );
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(3))
                .controller
                ?.text,
            '100,00',
          );
        },
      );
    });

    // ── 11.3 Navegação ────────────────────────────────────────────────────────

    group('11.3 Navegação e botão primário', () {
      testWidgets('Step3 exibe "Criar" em modo criação — não "Próximo"', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        expect(find.text('Criar'), findsOneWidget);
        expect(find.text('Próximo'), findsNothing);
      });

      testWidgets('Step3 exibe "Salvar" em modo edição', (tester) async {
        final existing = SlaTemplateRobot.buildExistingView();

        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard(existing: existing);
        await robot.tapNext(); // Step1 → Step2 (name pre-filled by existing)
        await robot.tapNext(); // Step2 → Step3

        expect(find.text('Salvar'), findsOneWidget);
        expect(find.text('Criar'), findsNothing);
      });

      testWidgets('Step3 renderiza exatamente 4 TextFormFields', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        expect(find.byType(TextFormField), findsNWidgets(4));
      });

      testWidgets('"Anterior" em Step3 volta para Step2', (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        await tapBack(tester);

        expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
      });
    });

    // ── 11.4 Decorações ───────────────────────────────────────────────────────

    group('11.4 Decorações — prefixos, sufixos e labels', () {
      testWidgets('prefixo "R\$" renderizado em 3 campos monetários do Step3', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        // Penalidade/min, Downgrade (flat), Valor Base Viagem each render prefix 'R$'
        expect(find.text(r'R$'), findsNWidgets(3));
      });

      testWidgets('sufixo "x" renderizado no campo Multiplicador No-Show', (
        tester,
      ) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        expect(find.text('x'), findsOneWidget);
      });

      testWidgets('labels corretas nos 4 campos do Step3', (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();
        await robot.fillStep1();
        await robot.tapNext();
        await robot.tapNext();

        expect(find.text('Penalidade/min'), findsOneWidget);
        expect(find.text('Downgrade (flat)'), findsOneWidget);
        expect(find.text('Multiplicador No-Show'), findsOneWidget);
        expect(find.text('Valor Base Viagem'), findsOneWidget);
      });
    });

    // ── 11.5 Submissão ────────────────────────────────────────────────────────

    group('11.5 Submissão — Criar dispara handler', () {
      testWidgets(
        '"Criar" com defaults válidos dispara handler.handle() uma vez',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          verify(
            () => handler.handle(
              organizationId: SlaTemplateRobot.defaultOrgId,
              sessionId: SlaTemplateRobot.defaultSessionId,
              name: 'Modelo Teste',
              description: any(named: 'description'),
              vertical: any(named: 'vertical'),
              penalties: any(named: 'penalties'),
              existingId: null,
              existingCreatedAt: null,
            ),
          ).called(1);
        },
      );

      testWidgets(
        '"Criar" converte vírgula decimal corretamente — R\$1,50 → 150 cents',
        (tester) async {
          dynamic captured;
          SlaTemplateRobot.stubHandler(
            handler,
            onCall: (args) => captured = args,
          );

          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          // Override delayPerMinCtl with a comma-formatted value
          await tester.enterText(find.byType(TextFormField).at(0), '1,50');
          await tester.pump();

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          // '1,50' → replaceAll(',','.') → '1.50' → double.parse(1.50) → *100 → round() = 150
          expect(captured.penalties.delayPenaltyPerMinuteCents, 150);
        },
      );
    });
  });
}
