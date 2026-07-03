// forensic_log_view_test.dart
//
// P2: testes de comportamento (TDD) — mask/reveal HMAC, copy, payload
// colapsado, replay. Goldens ficam em forensic_log_view_golden_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/features/admin/presentation/widgets/forensic_log_view.dart';
import 'package:veraprob/presentation/shared/ui/hash_text.dart';

// ── Shared fake data ────────────────────────────────────────────────────────

final _fakeLog = WebhookDeliveryLogView(
  id: '550e8400-e29b-41d4-a716-446655440000',
  endpointId: 'ep_123',
  eventType: 'sla.breached',
  payload: const {'tenant': 'ACME', 'amount': 50000},
  status: WebhookDeliveryStatusView.failed,
  attemptCount: 3,
  createdAt: DateTime.utc(2026, 7, 1, 10, 0, 0),
  ledgerEntryId: 'ledger_abc',
  signature: 'sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  lastError: 'Timeout after 10000ms\nSocketException: Connection refused',
);

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 400, child: child)),
      ),
    ),
  );
}

// ── Behaviour tests (P2 additions) ─────────────────────────────────────────

void main() {
  group('ForensicLogView — behaviour', () {
    testWidgets('HMAC signature masked by default', (tester) async {
      await tester.pumpWidget(_wrap(ForensicLogView(log: _fakeLog)));
      await tester.pumpAndSettle();

      // HashText masked → shows first8…last8, not full value
      expect(find.text(_fakeLog.signature!), findsNothing);
      // Reveal button is present (masked=true renders eye icon)
      expect(
        find.byKey(ValueKey('hash_text_reveal_${_fakeLog.signature.hashCode}')),
        findsOneWidget,
      );
    });

    testWidgets('toggle reveal shows full HMAC value', (tester) async {
      await tester.pumpWidget(_wrap(ForensicLogView(log: _fakeLog)));
      await tester.pumpAndSettle();

      final revealKey = ValueKey(
        'hash_text_reveal_${_fakeLog.signature.hashCode}',
      );
      await tester.tap(find.byKey(revealKey));
      await tester.pumpAndSettle();

      // After reveal, full value displayed
      expect(find.text(_fakeLog.signature!), findsOneWidget);
    });

    testWidgets('copy button present for Event ID', (tester) async {
      await tester.pumpWidget(_wrap(ForensicLogView(log: _fakeLog)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('hash_text_copy_${_fakeLog.id.hashCode}')),
        findsOneWidget,
      );
    });

    testWidgets('copy button present for Ledger Entry ID', (tester) async {
      await tester.pumpWidget(_wrap(ForensicLogView(log: _fakeLog)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          ValueKey('hash_text_copy_${_fakeLog.ledgerEntryId.hashCode}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'payload section uses HashText (3 HashText widgets: id, ledger, signature)',
      (tester) async {
        await tester.pumpWidget(_wrap(ForensicLogView(log: _fakeLog)));
        await tester.pumpAndSettle();

        // id + ledgerEntryId + signature = 3 HashText widgets
        expect(find.byType(HashText), findsNWidgets(3));
      },
    );

    testWidgets('payload is collapsed by default (ExpansionTile)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(ForensicLogView(log: _fakeLog)));
      await tester.pumpAndSettle();

      // Título 'Payload enviado' visível
      expect(find.text('Payload enviado'), findsOneWidget);

      // Conteúdo do JSON não deve estar visível enquanto colapsado
      // (ExpansionTile oculta children quando initiallyExpanded: false)
      expect(find.byType(ExpansionTile), findsOneWidget);
      final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
      expect(tile.initiallyExpanded, isFalse);
    });

    testWidgets('Replay Manual button present for failed status', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(ForensicLogView(log: _fakeLog)));
      await tester.pumpAndSettle();

      expect(find.text('Replay Manual'), findsOneWidget);
    });

    testWidgets('Replay Manual button absent for success status', (
      tester,
    ) async {
      final successLog = WebhookDeliveryLogView(
        id: _fakeLog.id,
        endpointId: _fakeLog.endpointId,
        eventType: _fakeLog.eventType,
        payload: _fakeLog.payload,
        status: WebhookDeliveryStatusView.success,
        attemptCount: 1,
        createdAt: _fakeLog.createdAt,
        ledgerEntryId: _fakeLog.ledgerEntryId,
        signature: _fakeLog.signature,
        lastError: null,
      );

      await tester.pumpWidget(_wrap(ForensicLogView(log: successLog)));
      await tester.pumpAndSettle();

      expect(find.text('Replay Manual'), findsNothing);
    });
  });

  // Goldens live in forensic_log_view_golden_test.dart (SSOT — wired into
  // scripts/generate_goldens.sh TEST_FILES; regen via `make goldens`).
}
