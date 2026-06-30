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

  group('2. Edit Mode — template existente pré-carregado', () {
    late MockSaveHandler handler;
    late SlaTemplateView existing;

    setUp(() {
      handler = MockSaveHandler();
      existing = SlaTemplateRobot.buildExistingView();
      SlaTemplateRobot.stubHandler(
        handler,
        returns: SlaTemplateRobot.buildFakeDomain(name: 'Modelo Existente'),
      );
    });

    testWidgets('título "Editar Modelo SLA" no modo edição', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard(existing: existing);

      expect(find.text('Editar Modelo SLA'), findsOneWidget);
      expect(find.text('Novo Modelo SLA'), findsNothing);
    });

    testWidgets('Step3 exibe botão "Salvar" em vez de "Criar"', (tester) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard(existing: existing);

      await robot.tapNext();
      await robot.tapNext();

      expect(find.text('Salvar'), findsOneWidget);
      expect(find.text('Criar'), findsNothing);
    });

    testWidgets('nome do template existente pré-preenchido no Step1', (
      tester,
    ) async {
      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard(existing: existing);

      final nameField = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(nameField.controller?.text, 'Modelo Existente');
    });

    testWidgets('handler recebe existingId do template ao salvar', (
      tester,
    ) async {
      String? capturedExistingId;
      SlaTemplateRobot.stubHandler(
        handler,
        onCall: (args) {
          capturedExistingId = args.existingId as String?;
        },
      );

      final robot = SlaTemplateRobot(tester, handler);
      await robot.bootstrapWizard(existing: existing);

      await robot.tapNext();
      await robot.tapNext();
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(capturedExistingId, equals(existing.id));
    });
  });
}
