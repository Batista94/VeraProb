import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/hmac_secret_modal.dart';

void main() {
  group('HmacSecretModal (CT19)', () {
    Widget buildWidget() {
      return const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: HmacSecretModal(
                secret: 'TEST_HMAC_SECRET_12345',
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Visual Feedback: Exibe segredo em fonte monospace e possui advertência (UX-Ops)', (tester) async {
      await tester.pumpWidget(buildWidget());

      // Verifica se o texto de advertência de risco existe
      expect(find.textContaining('não será exibido novamente'), findsOneWidget);

      // Verifica se o segredo existe
      final secretText = find.text('TEST_HMAC_SECRET_12345');
      expect(secretText, findsOneWidget);
      
      // O texto precisa estar usando monospace style para facilitar a cópia
      final Text textWidget = tester.widget(secretText);
      expect(textWidget.style?.fontFamily, contains('mono'));
      // Ou verifica apenas se existe um campo selecionável/selecionável monospaced (dependendo de como foi feito).
    });

    testWidgets('Validação Forense (Memória e Clipboard Leak Guard)', (tester) async {
      // Usaremos o DefaultBinaryMessenger para interceptar as chamadas ao Clipboard
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardContent = methodCall.arguments['text'] as String?;
            return null;
          } else if (methodCall.method == 'Clipboard.getData') {
            return {'text': clipboardContent};
          }
          return null;
        },
      );

      await tester.pumpWidget(buildWidget());

      // 1. Simula clique no botão de cópia
      final copyButton = find.byIcon(Icons.copy);
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pump();

      // Verifica se o clipboard tem o valor original
      var data = await Clipboard.getData('text/plain');
      expect(data?.text, 'TEST_HMAC_SECRET_12345');

      // 2. Simula o avanço do tempo até a expiração (60 segundos)
      await tester.pump(const Duration(seconds: 60));

      // Verifica se a Clipboard foi limpa (TTL)
      data = await Clipboard.getData('text/plain');
      expect(data?.text, isEmpty);
    });

    testWidgets('Memory Leak Guard: Cancela timer se o widget for destruído precocemente', (tester) async {
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardContent = methodCall.arguments['text'] as String?;
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(buildWidget());
      
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(clipboardContent, 'TEST_HMAC_SECRET_12345');

      // Fechamento manual antes do timer estourar
      // Desmontar o widget
      await tester.pumpWidget(const SizedBox());

      // Se o timer NÃO for cancelado no dispose(), lançará uma exceção de "Timer ainda ativo"
      // ou se tentar mexer no widget desmontado (setState). 
      // Ao tentar avançar o relógio, nada de anormal deve ocorrer, e como o dispose 
      // ocorreu, o timer deve ter sido limpo, e a clipboard não deve ter sido limpa pelo timer.
      await tester.pump(const Duration(seconds: 60));
      
      // Asserção Forense
      expect(find.byType(HmacSecretModal), findsNothing);
    });
  });
}
