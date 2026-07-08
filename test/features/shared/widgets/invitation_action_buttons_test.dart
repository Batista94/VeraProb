import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/shared/widgets/invitation_action_buttons.dart';

void main() {
  group('InvitationActionButtons', () {
    testWidgets('renders 3 IconButtons when token is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvitationActionButtons(
              token: 'fake-token',
              onResend: () {},
              onRevoke: () {},
            ),
          ),
        ),
      );

      expect(find.byType(IconButton), findsNWidgets(3));
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.send_outlined), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    });

    testWidgets('calls correct callbacks when pressed', (tester) async {
      bool copyCalled = false;
      bool resendCalled = false;
      bool revokeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvitationActionButtons(
              onCopyLink: () => copyCalled = true,
              onResend: () => resendCalled = true,
              onRevoke: () => revokeCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.copy_outlined));
      await tester.tap(find.byIcon(Icons.send_outlined));
      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pumpAndSettle();

      expect(copyCalled, isTrue);
      expect(resendCalled, isTrue);
      expect(revokeCalled, isTrue);
    });

    testWidgets('buttons are disabled when isDisabled is true', (tester) async {
      bool resendCalled = false;
      bool revokeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvitationActionButtons(
              token: 'token',
              isDisabled: true,
              onResend: () => resendCalled = true,
              onRevoke: () => revokeCalled = true,
            ),
          ),
        ),
      );

      final copyButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.copy_outlined),
      );
      final resendButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send_outlined),
      );
      final revokeButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.cancel_outlined),
      );

      expect(copyButton.onPressed, isNull);
      expect(resendButton.onPressed, isNull);
      expect(revokeButton.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.send_outlined));
      expect(resendCalled, isFalse);

      await tester.tap(find.byIcon(Icons.cancel_outlined));
      expect(revokeCalled, isFalse);
    });

    testWidgets('touch targets are at least 48x48', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvitationActionButtons(
              token: 'token',
              onResend: () {},
              onRevoke: () {},
            ),
          ),
        ),
      );

      final iconButtons = tester.widgetList<IconButton>(
        find.byType(IconButton),
      );
      for (final button in iconButtons) {
        expect(
          button.constraints,
          isNull,
        ); // default IconButton uses 48x48 min constraints internally
        // In Material 3, default IconButton has a minimum tap target size of 48x48
      }

      final copyFinder = find.byIcon(Icons.copy_outlined);
      // Even if icon is smaller, IconButton bounds will be larger, let's test the widget size
      final iconButtonFinder = find.ancestor(
        of: copyFinder,
        matching: find.byType(IconButton),
      );
      final buttonSize = tester.getSize(iconButtonFinder);
      expect(buttonSize.width, greaterThanOrEqualTo(48.0));
      expect(buttonSize.height, greaterThanOrEqualTo(48.0));
    });
  });
}
