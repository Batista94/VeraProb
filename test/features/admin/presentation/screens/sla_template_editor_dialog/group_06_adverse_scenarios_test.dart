import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'helpers/sla_template_robot.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(PenaltiesFormData.defaults());
    registerFallbackValue(TransportVertical.custom);
    registerFallbackValue(DateTime.utc(2024));
  });

  group('6. Cenários Adversos — falha no handler', () {
    testWidgets('handler lança Exception → SnackBar com VeraProbColors.error', (
      tester,
    ) async {
      final handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(
        handler,
        throws: Exception('Falha de conexão'),
      );

      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, VeraProbColors.error);
      expect(
        find.textContaining('Não foi possível salvar as alterações.'),
        findsOneWidget,
      );
    });

    testWidgets('dialog permanece aberto após falha no handler', (
      tester,
    ) async {
      final handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler, throws: Exception('Timeout'));

      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('_isSaving reseta para false após falha no handler', (
      tester,
    ) async {
      final handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler, throws: Exception('Server Error'));

      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Botão Cancelar volta a ser clicável
      final cancelBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancelar'),
      );
      expect(cancelBtn.onPressed, isNotNull);
    });

    testWidgets('após falha pode tentar salvar novamente', (tester) async {
      final handler = MockSaveHandler();
      var callCount = 0;
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
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw Exception('First attempt failed');
        return SlaTemplateRobot.buildFakeDomain();
      });

      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      // Primeira tentativa — falha
      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Dialog), findsOneWidget);

      // Segunda tentativa — sucesso
      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Dialog), findsNothing);
    });
  });
}
