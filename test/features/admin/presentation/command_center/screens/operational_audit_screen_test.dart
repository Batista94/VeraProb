import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/command_center/screens/operational_audit_screen.dart';
import 'package:veraprob/application/projections/models/audit_log_projection.dart';
import 'package:veraprob/state/providers/audit_providers.dart';
import 'package:veraprob/state/providers/shadow_providers.dart';

void main() {
  group('OperationalAuditScreen', () {
    Widget buildTestWidget() {
      return ProviderScope(
        overrides: [
          auditLogProjectionProvider.overrideWith(
            (ref) => const AuditLogProjection(entries: []),
          ),
          unlinkedShadowsProvider.overrideWith((ref) => []),
        ],
        child: const MaterialApp(home: OperationalAuditScreen()),
      );
    }

    testWidgets('Deve ser estritamente read-only (sem FAB)', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Nova Viagem'), findsNothing);
    });

    testWidgets('Deve possuir endDrawer sempre presente', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.endDrawer, isNotNull);
    });

    testWidgets('Colunas devem exibir Autor / Sistema', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Autor / Sistema'), findsOneWidget);
    });

    testWidgets(
      'load error shows sanitised domain message (UX-RAW-EXCEPTION guard)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              auditLogProjectionProvider.overrideWith(
                (ref) => Future.error('audit-fail'),
              ),
              unlinkedShadowsProvider.overrideWith((ref) => []),
            ],
            child: const MaterialApp(home: OperationalAuditScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Não foi possível carregar os registros de auditoria.'),
          findsOneWidget,
        );
        expect(find.textContaining('audit-fail'), findsNothing);
      },
    );
  });
}
