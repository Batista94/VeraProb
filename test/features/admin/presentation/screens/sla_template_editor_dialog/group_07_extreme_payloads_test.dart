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

  group('7. Payloads Extremos — robustez de entrada', () {
    late MockSaveHandler handler;

    setUp(() {
      handler = MockSaveHandler();
      SlaTemplateRobot.stubHandler(handler);
    });

    testWidgets('nome com caracteres especiais é aceito', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1(name: 'SLA #1 — Frota (BR/SP)');
      await robot.tapNext();

      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('valor decimal "50,00" aceito no campo R\$', (tester) async {
      String? capturedDelayPerMin;
      SlaTemplateRobot.stubHandler(
        handler,
        onCall: (args) {
          capturedDelayPerMin = args.penalties.delayPenaltyPerMinuteCents
              .toString();
        },
      );

      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      // Substitui Penalidade/min (1° campo Step3) por '50,00'
      await tester.enterText(find.byType(TextFormField).first, '50,00');
      await tester.pump();

      await tester.tap(find.text('Criar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // '50,00' → 5000 centavos
      expect(capturedDelayPerMin, '5000');
    });
  });
}
