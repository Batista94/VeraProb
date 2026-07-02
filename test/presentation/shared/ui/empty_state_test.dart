import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/empty_state.dart';

Widget _buildSubject(EmptyState widget) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(body: widget),
  );
}

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title, and description', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const EmptyState(
            key: Key('empty_state_basic'),
            icon: Icons.inbox_outlined,
            title: 'Nenhum item',
            description: 'Não há itens para exibir.',
          ),
        ),
      );

      expect(find.byKey(const Key('empty_state_basic')), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('Nenhum item'), findsOneWidget);
      expect(find.text('Não há itens para exibir.'), findsOneWidget);
    });

    testWidgets('does not render action when not provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const EmptyState(
            icon: Icons.search_off,
            title: 'Sem resultados',
            description: 'Tente outro filtro.',
          ),
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('renders action widget when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildSubject(
          EmptyState(
            icon: Icons.add_circle_outline,
            title: 'Sem endpoints',
            description: 'Crie um endpoint para começar.',
            action: FilledButton(
              key: const Key('empty_state_action_btn'),
              onPressed: () => tapped = true,
              child: const Text('Novo Endpoint'),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('empty_state_action_btn')), findsOneWidget);
      expect(find.text('Novo Endpoint'), findsOneWidget);

      await tester.tap(find.byKey(const Key('empty_state_action_btn')));
      expect(tapped, isTrue);
    });

    testWidgets('uses custom iconColor when provided', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const EmptyState(
            icon: Icons.warning_amber_outlined,
            title: 'Aviso',
            description: 'Algo de errado.',
            iconColor: VeraProbColors.warning,
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, VeraProbColors.warning);
    });

    testWidgets('uses textDisabled as default icon color', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Vazio',
            description: 'Sem dados.',
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, VeraProbColors.textDisabled);
    });
  });
}
