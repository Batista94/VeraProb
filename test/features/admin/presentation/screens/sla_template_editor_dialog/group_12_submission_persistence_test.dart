import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'helpers/sla_template_robot.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(PenaltiesFormData.defaults());
    registerFallbackValue(TransportVertical.custom);
    registerFallbackValue(DateTime.utc(2024));
  });

  group('12. Fase 5 — Submissão e Persistência', () {
    late MockSaveHandler handler;

    setUp(() {
      handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler);
    });

    // ── 12.1 E2E — payload completo verificado ────────────────────────────

    group('12.1 E2E — payload completo e precisão de cents', () {
      testWidgets(
        'payload financeiro: valores não-default convertidos com precisão exata',
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

          // Override all 4 financial fields with custom non-default values
          await tester.enterText(
            find.byType(TextFormField).at(0),
            '2,50',
          ); // delayPerMin: 2.50 BRL → 250 cents
          await tester.enterText(
            find.byType(TextFormField).at(1),
            '30,00',
          ); // downgrade: 30.00 BRL → 3000 cents
          await tester.enterText(
            find.byType(TextFormField).at(2),
            '2.0',
          ); // noShowMult: 2.0x → 20000 bps
          await tester.enterText(
            find.byType(TextFormField).at(3),
            '10,00',
          ); // baseTrip: 10.00 BRL → 1000 cents
          await tester.pump();

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(
            captured.penalties.delayPenaltyPerMinuteCents,
            250,
            reason: '"2,50" → 2.50 * 100 = 250',
          );
          expect(
            captured.penalties.downgradePenaltyFlatCents,
            3000,
            reason: '"30,00" → 30.00 * 100 = 3000',
          );
          expect(
            captured.penalties.noShowPenaltyBps,
            20000,
            reason: '"2.0" → (2.0 * 10000).round() = 20000',
          );
          expect(
            captured.penalties.baseTripValueCents,
            1000,
            reason: '"10,00" → 10.00 * 100 = 1000',
          );
        },
      );

      testWidgets(
        'payload identidade: organizationId, sessionId e name propagados (INV-1)',
        (tester) async {
          dynamic captured;
          SlaTemplateRobot.stubHandler(
            handler,
            onCall: (args) => captured = args,
          );

          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1(name: 'Modelo INV-1');
          await robot.tapNext();
          await robot.tapNext();

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(captured.organizationId, SlaTemplateRobot.defaultOrgId);
          expect(captured.sessionId, SlaTemplateRobot.defaultSessionId);
          expect(captured.name, 'Modelo INV-1');
          expect(captured.existingId, isNull);
          expect(captured.vertical, isNull);
        },
      );

      testWidgets(
        'dialog fecha após submit bem-sucedido — Navigator.pop chamado',
        (tester) async {
          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          expect(find.byType(Dialog), findsOneWidget);

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          expect(find.byType(Dialog), findsNothing);
        },
      );
    });

    // ── 12.2 Tratamento de Erros — sequência de estados ───────────────────

    group('12.2 Tratamento de Erros — sequência de estados', () {
      testWidgets(
        'submit: CircularProgressIndicator visível → desaparece após erro → SnackBar exibido',
        (tester) async {
          final completer = Completer<SlaTemplate>();
          when(
            () => handler.handle(
              organizationId: any(named: 'organizationId'),
              sessionId: any(named: 'sessionId'),
              name: any(named: 'name'),
              description: any(named: 'description'),
              vertical: any(named: 'vertical'),
              penalties: any(named: 'penalties'),
              existingId: any(named: 'existingId'),
              existingCreatedAt: any(named: 'existingCreatedAt'),
            ),
          ).thenAnswer((_) => completer.future);

          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.tap(find.text('Criar'));
          await tester.pump(); // single frame — Future still pending

          // Loading state: CircularProgressIndicator must be visible
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('Criar'), findsNothing);

          // Resolve with error
          completer.completeError(Exception('Erro de Conexão'));
          await tester.pumpAndSettle();

          // Loading gone, SnackBar with error message and correct background
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            find.text('Não foi possível salvar as alterações.'),
            findsOneWidget,
          );

          final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
          expect(snackBar.backgroundColor, VeraProbColors.error);
        },
      );

      testWidgets(
        'após erro: _isSaving=false restaurado — botão Criar volta ao estado normal',
        (tester) async {
          SlaTemplateRobot.stubHandler(handler, throws: Exception('falha'));

          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard();
          await robot.fillStep1();
          await robot.tapNext();
          await robot.tapNext();

          await tester.tap(find.text('Criar'));
          await tester.pumpAndSettle();

          // After error resolves: button text restored (CircularProgressIndicator gone)
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('Criar'), findsOneWidget);
        },
      );
    });

    // ── 12.3 Modo Edição — existingId, existingCreatedAt e pré-carga ──────

    group('12.3 Modo Edição — propagação de existingId e existingCreatedAt', () {
      testWidgets('existingId propagado ao handler — id do modelo existente', (
        tester,
      ) async {
        dynamic captured;
        SlaTemplateRobot.stubHandler(
          handler,
          onCall: (args) => captured = args,
        );

        final existing = SlaTemplateRobot.buildExistingView();

        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard(existing: existing);
        await robot.tapNext(); // Step1 → Step2 (name pre-filled)
        await robot.tapNext(); // Step2 → Step3

        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured.existingId, existing.id);
      });

      testWidgets(
        'existingCreatedAt propagado ao handler — timestamp original preservado (INV-12)',
        (tester) async {
          dynamic captured;
          SlaTemplateRobot.stubHandler(
            handler,
            onCall: (args) => captured = args,
          );

          final existing = SlaTemplateRobot.buildExistingView();

          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard(existing: existing);
          await robot.tapNext();
          await robot.tapNext();

          await tester.tap(find.text('Salvar'));
          await tester.pumpAndSettle();

          expect(captured, isNotNull);
          expect(captured.existingCreatedAt, existing.createdAt);
          expect(captured.existingCreatedAt, SlaTemplateRobot.defaultCreatedAt);
        },
      );

      testWidgets(
        'modo edição com penalties customizados — Step3 pré-carregado com valores corretos',
        (tester) async {
          // Build an existing view with specific financial values
          final customPenalties = SLAPenalties.create(
            noShowPenaltyBps: 20000, // 2.0x → displayed as '2.0'
            delayToleranceMinutes: 15,
            delayPenaltyPerMinute: const Money(250), // 250 cents → '2.50'
            downgradePenaltyFlat: const Money(7500), // 7500 cents → '75.00'
            noShowThresholdMinutes: 60,
            earlyArrivalToleranceMinutes: 5,
            dwellTimeMinutes: 3,
            gracePeriodMinutes: 0,
            baseTripValue: const Money(1000), // 1000 cents → '10.00'
          );
          final domain = SlaTemplate.reconstitute(
            id: 'edit-tmpl-001',
            organizationId: SlaTemplateRobot.defaultOrgId,
            name: 'Modelo Custom',
            penalties: customPenalties,
            createdAt: SlaTemplateRobot.defaultCreatedAt,
          );
          final existing = SlaTemplateView.fromDomain(domain);

          final robot = SlaTemplateRobot(tester, handler);
          await robot.bootstrapWizard(existing: existing);
          await robot.tapNext();
          await robot.tapNext();

          expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);

          // delayPenaltyPerMinuteCents=250 → (250/100).toStringAsFixed(2) = '2.50'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(0))
                .controller
                ?.text,
            '2.50',
            reason: '250 cents → 2.50',
          );
          // downgradePenaltyFlatCents=7500 → '75.00'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(1))
                .controller
                ?.text,
            '75.00',
            reason: '7500 cents → 75.00',
          );
          // noShowPenaltyBps=20000 → (20000/10000.0).toString() = '2.0'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(2))
                .controller
                ?.text,
            '2.0',
            reason: '20000 bps → 2.0',
          );
          // baseTripValueCents=1000 → '10.00'
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField).at(3))
                .controller
                ?.text,
            '10.00',
            reason: '1000 cents → 10.00',
          );
        },
      );
    });
  });
}
