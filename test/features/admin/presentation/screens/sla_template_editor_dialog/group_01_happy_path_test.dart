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

  group('1. Happy Path — wizard criar', () {
    late MockSaveHandler handler;

    setUp(() {
      handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler);
    });

    testWidgets('dialog renderiza como overlay — Dialog widget presente', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('Step1: título "Novo Modelo SLA" e indicador correto', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      expect(find.text('Novo Modelo SLA'), findsOneWidget);
      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('Step1 → Next → Step2 atualiza indicador de passo', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();

      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('Step2 → Next → Step3 atualiza indicador de passo', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      expect(find.text('Passo 3 de 3 — Financeiro'), findsOneWidget);
    });

    testWidgets('Step1 não mostra botão Anterior', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      expect(find.text('Anterior'), findsNothing);
    });

    testWidgets('Step2 mostra botão Anterior', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();

      expect(find.text('Anterior'), findsOneWidget);
    });

    testWidgets('Anterior no Step2 retorna para Step1', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);

      await tester.tap(find.text('Anterior'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('fluxo completo Criar → handler chamado 1x e dialog fechado', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      verify(
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
      ).called(1);

      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Cancelar fecha dialog sem chamar handler', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(Dialog), findsNothing);
      SlaTemplateRobot.verifyNeverCalled(handler);
    });
  });
}
