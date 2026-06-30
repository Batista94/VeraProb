import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_submission_notifier.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/features/dispute_portal/presentation/widgets/dispute_action_footer.dart';

const _justification = 'Justificativa muito muito longa para passar de vinte.';

Widget _buildFooter({
  required PortalSubmissionState state,
  VoidCallback? onSubmit,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DisputeActionFooter(
          state: state,
          onJustificationChanged: (_) {},
          onSubmit: onSubmit ?? () {},
          onAcknowledge: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('DisputeActionFooter — loading feedback (regression guards)', () {
    testWidgets('staging canSubmit: static "Enviar Contestação", no spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFooter(
          state: const PortalSubmissionStaging(justification: _justification),
        ),
      );

      expect(find.text('Enviar Contestação'), findsOneWidget);
      expect(find.text('Processando...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Enviar Contestação'),
            )
            .enabled,
        isTrue,
      );
    });

    testWidgets('staging short justification: submit button disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildFooter(
          state: const PortalSubmissionStaging(justification: 'curta'),
        ),
      );

      expect(find.text('Enviar Contestação'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Enviar Contestação'),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets(
      'hashing: button shows spinner + "Processando...", field disabled',
      (tester) async {
        await tester.pumpWidget(
          _buildFooter(state: const PortalSubmissionHashing()),
        );

        expect(find.text('Processando...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Enviar Contestação'), findsNothing);
        expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
          isFalse,
        );
      },
    );

    testWidgets(
      'uploading: button shows spinner + "Processando...", field disabled',
      (tester) async {
        await tester.pumpWidget(
          _buildFooter(state: const PortalSubmissionUploading()),
        );

        expect(find.text('Processando...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Enviar Contestação'), findsNothing);
        expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
          isFalse,
        );
      },
    );

    testWidgets(
      'retrying: button shows spinner + "Processando...", field disabled',
      (tester) async {
        await tester.pumpWidget(
          _buildFooter(
            state: const PortalSubmissionRetrying(attempt: 1, maxAttempts: 3),
          ),
        );

        expect(find.text('Processando...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Enviar Contestação'), findsNothing);
        expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
          isFalse,
        );
      },
    );

    testWidgets('uploading: submit callback never fires on tap', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        _buildFooter(
          state: const PortalSubmissionUploading(),
          onSubmit: () => called = true,
        ),
      );

      await tester.tap(find.byType(ElevatedButton).last);
      await tester.pump();

      expect(called, isFalse);
    });

    testWidgets(
      'error recoverable: "Enviar Contestação" restored, field enabled',
      (tester) async {
        await tester.pumpWidget(
          _buildFooter(
            state: const PortalSubmissionError(
              PortalDisputeException('Erro de conexão.'),
              PortalSubmissionStaging(justification: _justification),
            ),
          ),
        );

        expect(find.text('Enviar Contestação'), findsOneWidget);
        expect(find.text('Processando...'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
          isTrue,
        );
      },
    );
  });
}
