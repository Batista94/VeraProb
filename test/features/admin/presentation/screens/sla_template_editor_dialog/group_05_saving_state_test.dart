import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'helpers/sla_template_robot.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(PenaltiesFormData.defaults());
    registerFallbackValue(TransportVertical.custom);
    registerFallbackValue(DateTime.utc(2024));
  });

  group('5. Estado de Saving — UI de carregamento', () {
    testWidgets('CircularProgressIndicator visível enquanto handler processa', (
      tester,
    ) async {
      final handler = MockSaveHandler();
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
      await tester.pump(); // 1 frame — _isSaving = true

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(SlaTemplateRobot.buildFakeDomain());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('botão Cancelar desabilitado durante _isSaving', (
      tester,
    ) async {
      final handler = MockSaveHandler();
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
      await tester.pump();

      final cancelBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancelar'),
      );
      expect(cancelBtn.onPressed, isNull);

      completer.complete(SlaTemplateRobot.buildFakeDomain());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('_isSaving reseta para false após save bem-sucedido', (
      tester,
    ) async {
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

      // Dialog fechado — _isSaving resetou e Navigator.pop foi chamado
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
