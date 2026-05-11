import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/screens/widgets/audit_payload_diff_view.dart';

void main() {
  Widget buildSubject({
    Map<String, Object?>? payload,
    String? source,
    String? actorType,
    String? reason,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AuditPayloadDiffView(
            payload: payload,
            source: source,
            actorType: actorType,
            reason: reason,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. SEGURANÇA E INVARIANTES (Tríade CIA)
  // ═══════════════════════════════════════════════════════════════════════════

  group('CIA — Integridade', () {
    testWidgets('before == after → exibe "Nenhum campo alterado."', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'admin', 'active': true},
            'after': {'role': 'admin', 'active': true},
          },
        ),
      );

      expect(find.text('Nenhum campo alterado.'), findsOneWidget);
    });

    testWidgets('campo alterado aparece na diff table com valores corretos', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer'},
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(find.text('role'), findsOneWidget);
      expect(find.text('viewer'), findsOneWidget);
      expect(find.text('admin'), findsWidgets); // badge + cell
    });

    testWidgets('múltiplos campos alterados — todos listados', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer', 'active': 'true'},
            'after': {'role': 'admin', 'active': 'false'},
          },
        ),
      );

      expect(find.text('role'), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
    });

    testWidgets('campo inalterado NÃO aparece na diff', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'admin', 'name': 'João'},
            'after': {'role': 'viewer', 'name': 'João'},
          },
        ),
      );

      expect(find.text('role'), findsOneWidget);
      // 'name' unchanged → not in diff table
      final table = tester.widget<Table>(find.byType(Table));
      // Only 2 rows: header + 1 changed field
      expect(table.children.length, equals(2));
    });
  });

  group('CIA — Confidencialidade', () {
    testWidgets('payload null → exibe "Sem payload." sem crash', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(payload: null));

      expect(find.text('Sem payload.'), findsOneWidget);
    });

    testWidgets('context com email/user_id/org_id renderiza corretamente', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'context': {
              'email': 'admin@tenant-a.com',
              'user_id': 'uuid-123',
              'org_id': 'org-456',
            },
            'before': {'role': 'viewer'},
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(find.text('admin@tenant-a.com'), findsOneWidget);
      expect(find.text('uuid-123'), findsOneWidget);
      expect(find.text('org-456'), findsOneWidget);
    });

    testWidgets('context com valores null → exibe "—" sem crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'context': {'email': null, 'user_id': null},
            'before': {'x': '1'},
            'after': {'x': '2'},
          },
        ),
      );

      expect(find.text('—'), findsWidgets);
    });

    testWidgets('before é List (tipo errado) → fallback seguro', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': [1, 2, 3],
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(AuditPayloadDiffView), findsOneWidget);
    });

    testWidgets('context não-Map → ignora sem crash', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'context': 'string_invalida',
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('CIA — Não-Repúdio (ActorBadge)', () {
    testWidgets('source=system → badge "Sistema" com ícone robot', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'system',
        ),
      );

      expect(find.text('Sistema'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    });

    testWidgets('source=edge_function → badge "Sistema"', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'edge_function',
        ),
      );

      expect(find.text('Sistema'), findsOneWidget);
    });

    testWidgets('source=admin → badge "Administrador" com ícone shield', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'admin',
        ),
      );

      expect(find.text('Administrador'), findsOneWidget);
      expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOneWidget);
    });

    testWidgets('actorType IMPERSONATOR sobrescreve source=admin', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'admin',
          actorType: 'IMPERSONATOR',
        ),
      );

      expect(find.text('Impersonation'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.text('(admin)'), findsOneWidget);
    });

    testWidgets('actorType SYSTEM sobrescreve source=admin', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'admin',
          actorType: 'SYSTEM',
        ),
      );

      expect(find.text('Sistema'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    });

    testWidgets('actorType case-insensitive (lowercase)', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          actorType: 'impersonator',
        ),
      );

      expect(find.text('Impersonation'), findsOneWidget);
    });

    testWidgets('source e actorType ambos null → UNKNOWN (INV-21 fix)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
        ),
      );

      expect(find.text('Desconhecido'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. RESILIÊNCIA ADVERSARIAL
  // ═══════════════════════════════════════════════════════════════════════════

  group('Adversarial — Stress de Payload', () {
    testWidgets('500 campos alterados renderiza sem crash', (tester) async {
      final before = <String, Object?>{};
      final after = <String, Object?>{};
      for (var i = 0; i < 500; i++) {
        before['field_$i'] = 'old_$i';
        after['field_$i'] = 'new_$i';
      }

      await tester.pumpWidget(
        buildSubject(payload: {'before': before, 'after': after}),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(AuditPayloadDiffView), findsOneWidget);
    });

    testWidgets('payload vazio {} → exibe "Sem payload."', (tester) async {
      await tester.pumpWidget(buildSubject(payload: {}));

      expect(find.text('Sem payload.'), findsOneWidget);
    });
  });

  group('Adversarial — Malformed JSON', () {
    testWidgets('chaves inesperadas ignoradas sem crash', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'admin'},
            'after': {'role': 'viewer'},
            'unexpected_key': 'ignored',
            'another_garbage': 42,
          },
        ),
      );

      expect(find.text('role'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('before é String → fallback gracioso', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': 'not_a_map',
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('reason com XSS attempt → texto puro', (tester) async {
      const xss = '<script>alert("xss")</script>';
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          reason: xss,
        ),
      );

      expect(find.text(xss), findsOneWidget);
    });

    testWidgets('reason com Unicode longo (4000 chars) → sem overflow', (
      tester,
    ) async {
      final longReason = '🔒' * 1000;
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          reason: longReason,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('valor campo é Map aninhado → toString sem crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {
              'config': {'nested': true},
            },
            'after': {
              'config': {'nested': false},
            },
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('valor campo é List → toString sem crash', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {
              'tags': ['a', 'b'],
            },
            'after': {
              'tags': ['a', 'b', 'c'],
            },
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Adversarial — Edge Cases de Diff', () {
    testWidgets('before existe, after null → hasDiff=false → RawView', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'admin'},
            'after': null,
          },
        ),
      );

      // after null → empty map → hasDiff false → _RawView fallback
      expect(find.text('Nenhum campo alterado.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('before null, after existe → hasDiff=false → RawView', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': null,
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('campo em before mas não em after → aparece no diff', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'admin', 'extra': 'value'},
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(find.text('extra'), findsOneWidget);
      expect(find.text('value'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('campo em after mas não em before → aparece no diff', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'admin'},
            'after': {'role': 'admin', 'new_field': 'created'},
          },
        ),
      );

      expect(find.text('new_field'), findsOneWidget);
      expect(find.text('created'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. ACESSIBILIDADE PROFUNDA (A11y)
  // ═══════════════════════════════════════════════════════════════════════════

  group('A11y — Verificação Semântica', () {
    testWidgets('ActorBadge texto legível para screen readers', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'system',
        ),
      );

      expect(find.text('Sistema'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    });

    testWidgets('IMPERSONATOR badge tem cor de erro (alta visibilidade)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          actorType: 'IMPERSONATOR',
        ),
      );

      final textWidget = tester.widget<Text>(find.text('Impersonation'));
      expect(textWidget.style?.color, equals(VeraProbColors.error));
    });
  });

  group('A11y — Contraste e Cor', () {
    testWidgets('diff "Antes" usa cor error', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer'},
            'after': {'role': 'admin'},
          },
        ),
      );

      final selectables = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      final oldVal = selectables.firstWhere((w) => w.data == 'viewer');
      expect(oldVal.style?.color, equals(VeraProbColors.error));
    });

    testWidgets('diff "Depois" usa cor success', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer'},
            'after': {'role': 'new_admin'},
          },
        ),
      );

      final selectables = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      final newVal = selectables.firstWhere((w) => w.data == 'new_admin');
      expect(newVal.style?.color, equals(VeraProbColors.success));
    });

    testWidgets('table headers: Campo/Antes/Depois (dica posicional)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer'},
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(find.text('Campo'), findsOneWidget);
      expect(find.text('Antes'), findsOneWidget);
      expect(find.text('Depois'), findsOneWidget);
    });
  });

  group('A11y — Interação (SelectableText)', () {
    testWidgets('diff cell values usam SelectableText', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer'},
            'after': {'role': 'admin'},
          },
        ),
      );

      final selectables = find.byType(SelectableText);
      expect(selectables, findsWidgets);
    });

    testWidgets('context fields usam SelectableText', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'context': {'email': 'test@org.com'},
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
        ),
      );

      final selectables = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectables.where((w) => w.data == 'test@org.com'), isNotEmpty);
    });

    testWidgets('reason usa SelectableText', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          reason: 'Compliance XYZ-123',
        ),
      );

      final selectables = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      expect(
        selectables.where((w) => w.data == 'Compliance XYZ-123'),
        isNotEmpty,
      );
    });

    testWidgets('RawView values usam SelectableText', (tester) async {
      // RawView triggers when hasDiff=false but !isEmpty
      // Need: before non-empty + after empty → renders raw payload keys
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'ip': '192.168.1.1'},
          },
        ),
      );

      // _RawView renders payload entries as SelectableText
      final selectables = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      // Raw payload key 'before' rendered with its toString value
      expect(selectables, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. FIDELIDADE VISUAL E UI
  // ═══════════════════════════════════════════════════════════════════════════

  group('Visual — Design Tokens', () {
    testWidgets('"Sem payload." usa textSecondary', (tester) async {
      await tester.pumpWidget(buildSubject(payload: null));

      final text = tester.widget<Text>(find.text('Sem payload.'));
      expect(text.style?.color, equals(VeraProbColors.textSecondary));
    });

    testWidgets('"Nenhum campo alterado." usa textSecondary', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'x': '1'},
            'after': {'x': '1'},
          },
        ),
      );

      final text = tester.widget<Text>(find.text('Nenhum campo alterado.'));
      expect(text.style?.color, equals(VeraProbColors.textSecondary));
    });

    testWidgets('reason banner icon usa info color', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          reason: 'Test reason',
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.notes_outlined));
      expect(icon.color, equals(VeraProbColors.info));
    });

    testWidgets('SYSTEM badge usa info color', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'system',
        ),
      );

      final text = tester.widget<Text>(find.text('Sistema'));
      expect(text.style?.color, equals(VeraProbColors.info));
    });

    testWidgets('HUMAN badge usa secondary color', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'admin',
        ),
      );

      final text = tester.widget<Text>(find.text('Administrador'));
      expect(text.style?.color, equals(VeraProbColors.secondary));
    });
  });

  group('Visual — Responsividade', () {
    testWidgets('viewport estreito (320px) sem overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer', 'status': 'inactive'},
            'after': {'role': 'admin', 'status': 'active'},
          },
          source: 'admin',
          reason: 'Promoção de cargo',
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('viewport largo (1920px) sem distorção', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'role': 'viewer'},
            'after': {'role': 'admin'},
          },
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BONUS: Regression Guards
  // ═══════════════════════════════════════════════════════════════════════════

  group('Regression', () {
    testWidgets('reason vazio → banner NÃO renderiza', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          reason: '',
        ),
      );

      expect(find.byIcon(Icons.notes_outlined), findsNothing);
    });

    testWidgets('reason null → banner NÃO renderiza', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          reason: null,
        ),
      );

      expect(find.byIcon(Icons.notes_outlined), findsNothing);
    });

    testWidgets('source exibido entre parênteses', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: 'edge_function',
        ),
      );

      expect(find.text('(edge_function)'), findsOneWidget);
    });

    testWidgets('source null → sem parênteses', (tester) async {
      await tester.pumpWidget(
        buildSubject(
          payload: {
            'before': {'a': '1'},
            'after': {'a': '2'},
          },
          source: null,
        ),
      );

      expect(find.textContaining('('), findsNothing);
    });
  });
}
