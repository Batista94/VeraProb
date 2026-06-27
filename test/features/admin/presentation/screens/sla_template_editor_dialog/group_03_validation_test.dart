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

  group('3. Validação — campos obrigatórios e limites', () {
    late MockSaveHandler handler;

    setUp(() {
      handler = MockSaveHandler();
    });

    testWidgets('nome vazio → Obrigatório exibido, permanece Step1', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await tester.tap(find.text('Próximo'));
      await tester.pump();

      expect(find.text('Obrigatório'), findsOneWidget);
      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('nome com 101 chars → "Máx. 100 caracteres"', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await tester.enterText(find.byType(TextFormField).first, 'A' * 101);
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump();

      expect(find.text('Máx. 100 caracteres'), findsOneWidget);
      expect(find.text('Passo 1 de 3 — Identidade'), findsOneWidget);
    });

    testWidgets('nome exatamente 100 chars é válido → avança para Step2', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await tester.enterText(find.byType(TextFormField).first, 'A' * 100);
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Máx. 100 caracteres'), findsNothing);
      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('descrição vazia é aceita (campo opcional)', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      // Só preenche nome, deixa descrição vazia
      await tester.enterText(find.byType(TextFormField).first, 'Modelo X');
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('campo temporal vazio → Obrigatório, permanece Step2', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();

      // Limpa o primeiro campo do Step2 (Tolerância Atraso)
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pump();
      await tester.tap(find.text('Próximo'));
      await tester.pump();

      expect(find.text('Obrigatório'), findsOneWidget);
      expect(find.text('Passo 2 de 3 — Temporal'), findsOneWidget);
    });

    testWidgets('campo financeiro vazio → Obrigatório, permanece Step3', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard();

      await robot.fillStep1();
      await robot.tapNext();
      await robot.tapNext();

      // Limpa o primeiro campo do Step3 (Penalidade/min)
      await tester.enterText(find.byType(TextFormField).first, '');
      await tester.pump();
      await tester.tap(find.text('Criar'));
      await tester.pump();

      expect(find.text('Obrigatório'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      SlaTemplateRobot.verifyNeverCalled(handler);
    });
  });
}
