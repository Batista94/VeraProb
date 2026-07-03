import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/hash_text.dart';

Widget _buildSubject(HashText widget) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(body: Center(child: widget)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HashText', () {
    const fullValue = 'abcdef1234567890abcdef1234567890';

    testWidgets('renders full value when not masked', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          const HashText(key: Key('hash_text_full'), value: fullValue),
        ),
      );

      expect(find.text(fullValue), findsOneWidget);
    });

    testWidgets('renders masked value by default when masked=true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          const HashText(
            key: Key('hash_text_masked'),
            value: fullValue,
            masked: true,
          ),
        ),
      );

      // Shows first8…last8
      expect(find.text('abcdef12…34567890'), findsOneWidget);
      expect(find.text(fullValue), findsNothing);
    });

    testWidgets('reveals full value after tapping reveal button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(const HashText(value: fullValue, masked: true)),
      );

      // Initially masked
      expect(find.text('abcdef12…34567890'), findsOneWidget);

      // Tap reveal
      await tester.tap(
        find.byKey(ValueKey('hash_text_reveal_${fullValue.hashCode}')),
      );
      await tester.pumpAndSettle();

      // Full value shown
      expect(find.text(fullValue), findsOneWidget);
    });

    testWidgets('masks again after second reveal tap', (tester) async {
      await tester.pumpWidget(
        _buildSubject(const HashText(value: fullValue, masked: true)),
      );

      final revealKey = ValueKey('hash_text_reveal_${fullValue.hashCode}');

      await tester.tap(find.byKey(revealKey));
      await tester.pumpAndSettle();
      expect(find.text(fullValue), findsOneWidget);

      await tester.tap(find.byKey(revealKey));
      await tester.pumpAndSettle();
      expect(find.text('abcdef12…34567890'), findsOneWidget);
    });

    testWidgets('copy button writes full value to clipboard', (tester) async {
      // Use SystemChannels.platform — the channel Clipboard.setData actually
      // routes through. Pattern established in org_secret_card_test.dart.
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (message) async {
          if (message.method == 'Clipboard.setData') {
            clipboardContent =
                (message.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(_buildSubject(const HashText(value: fullValue)));

      await tester.tap(
        find.byKey(ValueKey('hash_text_copy_${fullValue.hashCode}')),
      );
      await tester.pumpAndSettle();

      expect(clipboardContent, equals(fullValue));
    });

    testWidgets('copy button copies full value even when masked', (
      tester,
    ) async {
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (message) async {
          if (message.method == 'Clipboard.setData') {
            clipboardContent =
                (message.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        _buildSubject(const HashText(value: fullValue, masked: true)),
      );

      await tester.tap(
        find.byKey(ValueKey('hash_text_copy_${fullValue.hashCode}')),
      );
      await tester.pumpAndSettle();

      // Always copies the full value, not the masked display
      expect(clipboardContent, equals(fullValue));
    });

    testWidgets('does not show copy button when showCopyButton=false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(const HashText(value: fullValue, showCopyButton: false)),
      );

      expect(
        find.byKey(ValueKey('hash_text_copy_${fullValue.hashCode}')),
        findsNothing,
      );
    });

    testWidgets('short values are not truncated when masked', (tester) async {
      const shortValue = 'abc123';
      await tester.pumpWidget(
        _buildSubject(const HashText(value: shortValue, masked: true)),
      );

      // Short values (<=16 chars) shown as-is
      expect(find.text(shortValue), findsOneWidget);
    });
  });
}
