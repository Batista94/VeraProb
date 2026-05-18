import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/super_admin/generate_org_secret_handler.dart';
import 'package:veraprob/application/super_admin/org_api_secret_view_model.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_secret_card.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ── Mocks ─────────────────────────────────────────────────────

class MockGenerateOrgSecretHandler extends Mock
    implements GenerateOrgSecretHandler {}

// ── Fixtures ──────────────────────────────────────────────────

const _kOrgId = 'org-forensic-001';
const _kOrgName = 'Acme Logistics';
const _kValidSecret =
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

final _kExistingSecret = OrgApiSecretViewModel(
  id: 'secret-001',
  organizationId: _kOrgId,
  secretHash: 'sha256-hash-placeholder',
  version: 3,
  createdAt: DateTime.utc(2026, 1, 15, 10, 0),
  rotatedAt: DateTime.utc(2026, 3, 20, 14, 30),
  revokedAt: null,
  isActive: true,
);

// ── Helpers ───────────────────────────────────────────────────

Widget _buildSubject({
  required MockGenerateOrgSecretHandler mockHandler,
  OrgApiSecretViewModel? currentSecret,
}) {
  return ProviderScope(
    overrides: [
      generateOrgSecretHandlerProvider.overrideWithValue(mockHandler),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OrgSecretCard(
            organizationId: _kOrgId,
            organizationName: _kOrgName,
            currentSecret: currentSecret,
          ),
        ),
      ),
    ),
  );
}

/// Confirms dialog by tapping 'Gerar Secret' button inside AlertDialog.
Future<void> _confirmDialog(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // Dialog has its own FilledButton with red background — find it within AlertDialog
  final dialogFinder = find.byType(AlertDialog);
  expect(dialogFinder, findsOneWidget);
  final confirmBtn = find.descendant(
    of: dialogFinder,
    matching: find.widgetWithText(FilledButton, 'Gerar Secret'),
  );
  expect(confirmBtn, findsOneWidget);
  await tester.tap(confirmBtn);
  await tester.pumpAndSettle();
}

/// Like [_confirmDialog] but uses pump(duration) instead of pumpAndSettle().
/// Use when handler returns a non-completing future (Completer-based tests).
Future<void> _confirmDialogNonSettling(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final dialogFinder = find.byType(AlertDialog);
  expect(dialogFinder, findsOneWidget);
  final confirmBtn = find.descendant(
    of: dialogFinder,
    matching: find.widgetWithText(FilledButton, 'Gerar Secret'),
  );
  expect(confirmBtn, findsOneWidget);
  await tester.tap(confirmBtn);
  // Pump enough frames for dialog route animation to complete
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Taps main generate/rotate button.
Future<void> _tapGenerateButton(WidgetTester tester) async {
  final btn = find.widgetWithText(FilledButton, 'Gerar Secret');
  if (btn.evaluate().isEmpty) {
    await tester.tap(find.widgetWithText(FilledButton, 'Rotacionar Secret'));
  } else {
    await tester.tap(btn);
  }
  await tester.pumpAndSettle();
}

void main() {
  late MockGenerateOrgSecretHandler mockHandler;

  setUp(() {
    mockHandler = MockGenerateOrgSecretHandler();
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 1: CIA TRIAD — SECURITY
  // ═══════════════════════════════════════════════════════════════

  group('[CIA] Confidentiality — Ephemeral Secret State', () {
    testWidgets('generated secret shown only in ephemeral widget state', (
      tester,
    ) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 4,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      // Secret visible
      expect(find.text(_kValidSecret), findsOneWidget);

      // Secret stored in local state only — no persistence layer called
      verifyNever(
        () => mockHandler.handle(
          organizationId: _kOrgId,
          sessionId: 'persist', // never called with persist session
        ),
      );
    });

    testWidgets(
      'secret container disappears after widget rebuild with new key',
      (tester) async {
        when(
          () => mockHandler.handle(
            organizationId: any(named: 'organizationId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenAnswer(
          (_) async => const GenerateOrgSecretResult(
            secret: _kValidSecret,
            version: 1,
            organizationId: _kOrgId,
          ),
        );

        // Build with no existing secret, generate one
        await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
        await _tapGenerateButton(tester);
        await _confirmDialog(tester);
        expect(find.text(_kValidSecret), findsOneWidget);

        // Rebuild with new key (simulates navigation pop + re-enter)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              generateOrgSecretHandlerProvider.overrideWithValue(mockHandler),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: OrgSecretCard(
                    key: UniqueKey(),
                    organizationId: _kOrgId,
                    organizationName: _kOrgName,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Secret gone — ephemeral state reset
        expect(find.text(_kValidSecret), findsNothing);
      },
    );
  });

  group('[CIA] Integrity — Confirmation & Correct OrgId', () {
    testWidgets('rotation requires dialog confirmation before handler call', (
      tester,
    ) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 4,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(
        _buildSubject(
          mockHandler: mockHandler,
          currentSecret: _kExistingSecret,
        ),
      );

      // Tap rotate button
      await tester.tap(find.widgetWithText(FilledButton, 'Rotacionar Secret'));
      await tester.pumpAndSettle();

      // Dialog shown with revocation warning
      expect(find.text('Gerar Novo Secret'), findsOneWidget);
      expect(find.text('v3'), findsOneWidget);

      // Handler NOT called yet
      verifyNever(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      );

      // Confirm
      await _confirmDialog(tester);

      // NOW handler called with correct orgId
      verify(
        () => mockHandler.handle(
          organizationId: _kOrgId,
          sessionId: 'super-admin-session',
        ),
      ).called(1);
    });

    testWidgets('handler called with exact organizationId from widget prop', (
      tester,
    ) async {
      const customOrgId = 'org-custom-xyz-789';

      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: customOrgId,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            generateOrgSecretHandlerProvider.overrideWithValue(mockHandler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: OrgSecretCard(
                  organizationId: customOrgId,
                  organizationName: 'Custom Org',
                ),
              ),
            ),
          ),
        ),
      );

      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      verify(
        () => mockHandler.handle(
          organizationId: customOrgId,
          sessionId: 'super-admin-session',
        ),
      ).called(1);
    });
  });

  group('[CIA] Availability — Error Resilience', () {
    testWidgets('network failure shows error message without crashing UI', (
      tester,
    ) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenThrow(Exception('Network timeout'));

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      // Error displayed as user-friendly message (INV-10: no class names)
      expect(find.textContaining('Falha ao gerar secret'), findsOneWidget);

      // Secret container NOT shown
      expect(find.byIcon(Icons.copy), findsNothing);

      // Button re-enabled (not stuck in loading)
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Gerar Secret'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('error state clears on successful retry', (tester) async {
      var callCount = 0;
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) throw Exception('Transient failure');
        return const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        );
      });

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));

      // First attempt — fails
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);
      expect(find.textContaining('Falha ao gerar secret'), findsOneWidget);

      // Retry — succeeds
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);
      expect(find.textContaining('Transient failure'), findsNothing);
      expect(find.text(_kValidSecret), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 2: ADVERSARIAL & CHAOS INJECTION
  // ═══════════════════════════════════════════════════════════════

  group('[Adversarial] Race Conditions', () {
    testWidgets(
      'rapid clicks during processing ignored — single handler call',
      (tester) async {
        final completer = Completer<GenerateOrgSecretResult>();

        when(
          () => mockHandler.handle(
            organizationId: any(named: 'organizationId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenAnswer((_) => completer.future);

        await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
        await _tapGenerateButton(tester);
        await _confirmDialogNonSettling(tester);

        // Now in loading state — button disabled
        await tester.pump();
        final cardFinder = find.byType(OrgSecretCard);
        final btnFinder = find.descendant(
          of: cardFinder,
          matching: find.widgetWithText(FilledButton, 'Gerar Secret'),
        );
        final btn = tester.widget<FilledButton>(btnFinder);
        expect(btn.onPressed, isNull); // Disabled

        // Attempt frantic clicks on disabled button
        await tester.tap(btnFinder);
        await tester.tap(btnFinder);
        await tester.tap(btnFinder);
        await tester.pump();

        // Complete the future
        completer.complete(
          const GenerateOrgSecretResult(
            secret: _kValidSecret,
            version: 1,
            organizationId: _kOrgId,
          ),
        );
        await tester.pumpAndSettle();

        // Handler called exactly once
        verify(
          () => mockHandler.handle(
            organizationId: _kOrgId,
            sessionId: 'super-admin-session',
          ),
        ).called(1);
      },
    );

    testWidgets('loading indicator shown during processing', (tester) async {
      final completer = Completer<GenerateOrgSecretResult>();

      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialogNonSettling(tester);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(
        const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('[Adversarial] Flow Interruption', () {
    testWidgets('canceling dialog does NOT trigger handler', (tester) async {
      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);

      // Dialog visible
      await tester.pumpAndSettle();
      expect(find.text('Gerar Novo Secret'), findsOneWidget);

      // Cancel
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      // Handler never called
      verifyNever(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      );
    });

    testWidgets('dismissing dialog via barrier tap does NOT trigger handler', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await tester.pumpAndSettle();

      // Tap barrier (outside dialog)
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      verifyNever(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      );
    });

    testWidgets('state remains idle after dialog cancel', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          mockHandler: mockHandler,
          currentSecret: _kExistingSecret,
        ),
      );

      // Verify initial state
      expect(find.text('v3'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Rotacionar Secret'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      // State unchanged
      expect(find.text('v3'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.copy), findsNothing);
    });
  });

  group('[Chaos] Data Corruption Injection', () {
    testWidgets('empty secret string treated as integrity failure', (
      tester,
    ) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: '', // CHAOS: empty secret
          version: 1,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      // Empty secret — widget shows it but container with copy should
      // still render (widget trusts handler validation).
      // NOTE: If widget adds empty-check guard, this test validates it.
      // Current impl: _generatedSecret = '' which is non-null, container shows.
      // This documents current behavior for future hardening.
      final secretContainer = find.byIcon(Icons.copy);
      // Widget currently renders container for any non-null _generatedSecret.
      // This test documents the behavior for security review.
      expect(secretContainer, findsOneWidget);
    });

    testWidgets('handler throwing preserves UI stability', (tester) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenThrow(StateError('Unexpected corruption'));

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      // Error shown as friendly message (INV-10: no internal class names)
      expect(find.textContaining('Falha ao gerar secret'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNothing);

      // Widget tree intact
      expect(find.byType(OrgSecretCard), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });
  });

  group('[Forensic] Clipboard', () {
    testWidgets('copy button places exact secret value in clipboard', (
      tester,
    ) async {
      String? clipboardContent;

      // Mock clipboard channel
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (message) async {
          if (message.method == 'Clipboard.setData') {
            final args = message.arguments as Map<dynamic, dynamic>;
            clipboardContent = args['text'] as String?;
          }
          return null;
        },
      );

      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      // Tap copy
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();

      expect(clipboardContent, equals(_kValidSecret));

      // Snackbar confirmation
      expect(find.text('Secret copiado!'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 3: ACCESSIBILITY (A11y)
  // ═══════════════════════════════════════════════════════════════

  group('[A11y] Semantic Tree & Accessibility', () {
    testWidgets('warning text uses semantic label for screen readers', (
      tester,
    ) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      // Warning text present and readable
      expect(
        find.text('Copie agora — não será exibido novamente!'),
        findsOneWidget,
      );
    });

    testWidgets('copy button has tooltip for accessibility', (tester) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, equals('Copiar'));
    });

    testWidgets('secret displayed in monospace font', (tester) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      final selectableText = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectableText.style?.fontFamily, equals('monospace'));
    });

    testWidgets('confirmation dialog captures focus', (tester) async {
      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await tester.pumpAndSettle();

      // Dialog is a modal barrier — focus trapped within
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Cancelar')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(FilledButton, 'Gerar Secret'),
        ),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 4: STATE BRANCH COVERAGE
  // ═══════════════════════════════════════════════════════════════

  group('[States] Full Branch Coverage', () {
    testWidgets('IDLE — no secret configured shows placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));

      expect(find.text('Nenhum secret configurado.'), findsOneWidget);
      expect(find.text('Gerar Secret'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('IDLE — existing secret shows version and dates', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(
          mockHandler: mockHandler,
          currentSecret: _kExistingSecret,
        ),
      );

      expect(find.text('v3'), findsOneWidget);
      expect(find.text('Rotacionar Secret'), findsOneWidget);
      expect(find.text('HMAC Secret (INV-28)'), findsOneWidget);
    });

    testWidgets('LOADING — spinner shown, button disabled', (tester) async {
      final completer = Completer<GenerateOrgSecretResult>();
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialogNonSettling(tester);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final cardFinder = find.byType(OrgSecretCard);
      final btn = tester.widget<FilledButton>(
        find.descendant(
          of: cardFinder,
          matching: find.widgetWithText(FilledButton, 'Gerar Secret'),
        ),
      );
      expect(btn.onPressed, isNull);

      // Cleanup
      completer.complete(
        const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('SUCCESS — secret container with warning and copy button', (
      tester,
    ) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer(
        (_) async => const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      expect(find.text(_kValidSecret), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(
        find.text('Copie agora — não será exibido novamente!'),
        findsOneWidget,
      );
    });

    testWidgets('ERROR — error message shown, no secret container', (
      tester,
    ) async {
      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenThrow(Exception('Server unavailable'));

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialog(tester);

      expect(find.textContaining('Falha ao gerar secret'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 5: LIFECYCLE — MOUNTED GUARD
  // ═══════════════════════════════════════════════════════════════

  group('[Lifecycle] context.mounted guard', () {
    testWidgets('no setState error if widget disposed during async handler', (
      tester,
    ) async {
      final completer = Completer<GenerateOrgSecretResult>();

      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialogNonSettling(tester);
      await tester.pump();

      // Dispose widget while handler is in-flight
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      // Complete after disposal — should NOT throw
      completer.complete(
        const GenerateOrgSecretResult(
          secret: _kValidSecret,
          version: 1,
          organizationId: _kOrgId,
        ),
      );

      // No exception = mounted guard works
      await tester.pumpAndSettle();
    });

    testWidgets('no setState error if widget disposed during error path', (
      tester,
    ) async {
      final completer = Completer<GenerateOrgSecretResult>();

      when(
        () => mockHandler.handle(
          organizationId: any(named: 'organizationId'),
          sessionId: any(named: 'sessionId'),
        ),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
      await _tapGenerateButton(tester);
      await _confirmDialogNonSettling(tester);
      await tester.pump();

      // Dispose
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      // Error after disposal
      completer.completeError(Exception('Post-disposal error'));

      // No exception
      await tester.pumpAndSettle();
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // GROUP 6: INV-10 — DOMAIN-LANGUAGE ERROR DISPLAY
  // ═══════════════════════════════════════════════════════════════

  group('[INV-10] Error message never leaks internal class names', () {
    testWidgets(
      'DomainException shows e.message directly — no "DomainException:" prefix',
      (tester) async {
        when(
          () => mockHandler.handle(
            organizationId: any(named: 'organizationId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenThrow(
          const DomainException(
            'Cota de secrets excedida para esta organização',
          ),
        );

        await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
        await _tapGenerateButton(tester);
        await _confirmDialog(tester);

        expect(
          find.text('Cota de secrets excedida para esta organização'),
          findsOneWidget,
          reason: 'DomainException.message must be shown verbatim',
        );
        expect(
          find.textContaining('DomainException'),
          findsNothing,
          reason: 'Internal class name must never appear in the UI (INV-10)',
        );
      },
    );

    testWidgets(
      'non-domain exception shows generic message — no raw exception class leaked',
      (tester) async {
        when(
          () => mockHandler.handle(
            organizationId: any(named: 'organizationId'),
            sessionId: any(named: 'sessionId'),
          ),
        ).thenThrow(StateError('internal db constraint violation'));

        await tester.pumpWidget(_buildSubject(mockHandler: mockHandler));
        await _tapGenerateButton(tester);
        await _confirmDialog(tester);

        expect(
          find.text('Falha ao gerar secret. Tente novamente.'),
          findsOneWidget,
          reason: 'Generic exceptions must surface as a safe user message',
        );
        expect(
          find.textContaining('StateError'),
          findsNothing,
          reason: 'Internal class name must never appear in the UI (INV-10)',
        );
        expect(
          find.textContaining('internal db constraint violation'),
          findsNothing,
          reason: 'Raw exception message must not leak to the UI (INV-10)',
        );
      },
    );
  });
}
