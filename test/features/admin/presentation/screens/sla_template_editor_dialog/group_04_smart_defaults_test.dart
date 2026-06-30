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

  group('4. Smart Defaults — troca de Vertical', () {
    late MockSaveHandler handler;

    setUp(() {
      handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler);
    });

    testWidgets(
      'selecionar CargaSeca → delayToleranceMinutes muda de 15 para 30',
      (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        // Valor inicial do campo no Step1 — controller _delayTolCtl = '15'
        // Seleciona CargaSeca (SmartDefaults: delayToleranceMinutes = 30)
        await robot.selectVertical(TransportVertical.cargaSeca);

        await robot.fillStep1(name: 'Modelo Carga');
        await robot.tapNext(); // vai para Step2

        // Primeiro campo do Step2 = Tolerância Atraso = _delayTolCtl
        final firstField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(firstField.controller?.text, '30');
      },
    );

    testWidgets(
      'selecionar Escolar → noShowThresholdMinutes muda de 60 para 20',
      (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        await robot.selectVertical(TransportVertical.escolar);

        await robot.fillStep1(name: 'Modelo Escolar');
        await robot.tapNext(); // vai para Step2

        // Segundo campo do Step2 = Limiar No-Show = _noShowThreshCtl
        final secondField = tester.widget<TextFormField>(
          find.byType(TextFormField).at(1),
        );
        expect(secondField.controller?.text, '20');
      },
    );

    testWidgets(
      'selecionar Personalizado (custom) NÃO altera valores dos campos',
      (tester) async {
        final robot = SlaTemplateRobot(tester, handler);
        await robot.bootstrapWizard();

        // Primeiro seleciona CargaSeca (delayTol → 30)
        await robot.selectVertical(TransportVertical.cargaSeca);

        // Agora seleciona Personalizado — NÃO deve re-aplicar defaults
        await robot.selectVertical(TransportVertical.custom);

        await robot.fillStep1(name: 'Modelo Custom');
        await robot.tapNext();

        // Campo ainda deve ter '30' (CargaSeca default), não '15' (initial)
        final firstField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(firstField.controller?.text, '30');
      },
    );
  });
}
