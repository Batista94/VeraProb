// webhook_management_screen_test.dart
//
// TDD P2: testes escritos ANTES da refatoração da tela.
// Cobre: split wide, stack narrow, seleção, empty state, header UAT.
// Seletores key-based conforme decisões P2.
// Providers fakeados via ProviderScope overrides (sem infra real).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/features/admin/presentation/screens/webhook_management_screen.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

// ── Fake data ──────────────────────────────────────────────────────────────

WebhookEndpointView _ep(String id) => WebhookEndpointView(
  id: id,
  url: 'https://erp.acme.com/webhooks/$id',
  isActive: true,
  createdAt: DateTime.utc(2026, 1, 1),
  totalLogs: 10,
  pendingCount: 0,
  deliveringCount: 0,
  successCount: 10,
  failedCount: 0,
  deadCount: 0,
);

// ── Widget builder ─────────────────────────────────────────────────────────

Widget _buildSut({
  List<WebhookEndpointView> endpoints = const [],
  String? selectedId,
  double width = 1200,
}) {
  return ProviderScope(
    overrides: [
      webhookEndpointHealthProvider.overrideWith((_) async => endpoints),
      selectedEndpointIdProvider.overrideWith(
        () => _FakeSelectedEndpointIdNotifier(selectedId),
      ),
      deliveryLogFilterProvider.overrideWith(() => DeliveryLogFilterNotifier()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: width, child: const WebhookManagementScreen()),
      ),
    ),
  );
}

class _FakeSelectedEndpointIdNotifier extends SelectedEndpointIdNotifier {
  final String? _initial;
  _FakeSelectedEndpointIdNotifier(this._initial);
  @override
  String? build() => _initial;
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('WebhookManagementScreen', () {
    group('header', () {
      testWidgets('contains UAT-frozen label', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(_buildSut(endpoints: [_ep('ep1')]));
        await tester.pumpAndSettle();

        expect(
          find.text('Configurações de Integração (Webhooks)'),
          findsOneWidget,
        );
      });

      testWidgets('"Novo Endpoint" CTA button present', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(_buildSut(endpoints: [_ep('ep1')]));
        await tester.pumpAndSettle();

        expect(find.text('Novo Endpoint'), findsOneWidget);
      });

      testWidgets('no duplicate Scaffold (no nested AppBar)', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(_buildSut());
        await tester.pumpAndSettle();

        // Only the shell AppBar — none with title 'Webhook Endpoints'
        expect(find.text('Webhook Endpoints'), findsNothing);
      });
    });

    group('wide layout (>900px)', () {
      testWidgets('shows both master and detail areas', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(
          _buildSut(endpoints: [_ep('ep1')], width: 1200),
        );
        await tester.pumpAndSettle();

        // VerticalDivider present = split layout
        expect(find.byType(VerticalDivider), findsOneWidget);
      });
    });

    group('narrow layout (<=900px)', () {
      testWidgets('no selection: shows only endpoint list', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 900));
        await tester.pumpWidget(_buildSut(endpoints: [_ep('ep1')], width: 600));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('master-detail-back')), findsNothing);
      });

      testWidgets('with selection: back button visible', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 900));
        await tester.pumpWidget(
          _buildSut(endpoints: [_ep('ep1')], selectedId: 'ep1', width: 600),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('master-detail-back')),
          findsOneWidget,
        );
      });
    });

    group('empty state', () {
      testWidgets('shows EmptyState when no endpoints', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        await tester.pumpWidget(_buildSut());
        await tester.pumpAndSettle();

        expect(find.text('Nenhum endpoint configurado'), findsOneWidget);
      });
    });
  });
}
