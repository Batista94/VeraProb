// endpoint_list_panel.dart
//
// Master panel for WebhookManagementScreen.
// Extracted from the monolithic webhook_management_screen.dart (P2 redesign).
//
// Flows create/rotate intactos — apenas movidos do screen-level para cá.
// WASM-CONTEXT-LEAK: navigator/messenger capturados PRÉ-await (já verificado).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/create_endpoint_dialog.dart';
import 'package:veraprob/features/admin/presentation/widgets/reveal_secret_modal.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

/// Master panel: list of webhook endpoints with create/rotate flows.
class EndpointListPanel extends ConsumerWidget {
  const EndpointListPanel({super.key});

  // ── Flows (intactos — comportamento preservado) ─────────────────────────

  Future<void> _createEndpointFlow(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreateEndpointDialog(),
    );
    if (created != true || !context.mounted) return;
    await _showRevealModal(context, RevealAction.provision);
  }

  Future<void> _showRevealModal(
    BuildContext context,
    RevealAction action,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (_) => RevealSecretModal(action: action),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpointsAsync = ref.watch(webhookEndpointHealthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: endpointsAsync.when(
            data: (endpoints) => _buildList(context, endpoints, ref),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) =>
                const Center(child: Text('Falha ao carregar endpoints')),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    List<WebhookEndpointView> endpoints,
    WidgetRef ref,
  ) {
    if (endpoints.isEmpty) {
      return EmptyState(
        icon: Icons.webhook_outlined,
        title: 'Nenhum endpoint configurado',
        description:
            'Crie um endpoint HTTPS para receber os vereditos selados via webhook.',
        action: FilledButton.icon(
          onPressed: () => _createEndpointFlow(context),
          icon: const Icon(Icons.add),
          label: const Text('Novo Endpoint'),
        ),
      );
    }

    final selectedId = ref.watch(selectedEndpointIdProvider);

    return ListView.builder(
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final ep = endpoints[index];
        final isSelected = ep.id == selectedId;
        return _EndpointTile(
          endpoint: ep,
          isSelected: isSelected,
          onTap: () =>
              ref.read(selectedEndpointIdProvider.notifier).select(ep.id),
        );
      },
    );
  }
}

// ── Endpoint tile ───────────────────────────────────────────────────────────

class _EndpointTile extends StatelessWidget {
  const _EndpointTile({
    required this.endpoint,
    required this.isSelected,
    required this.onTap,
  });

  final WebhookEndpointView endpoint;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isSelected ? VeraProbColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: ListTile(
        selected: isSelected,
        selectedTileColor: VeraProbColors.surfaceElevated,
        title: HashText(value: endpoint.url, showCopyButton: true),
        subtitle: _buildStatusChips(endpoint),
        onTap: onTap,
      ),
    );
  }

  Widget? _buildStatusChips(WebhookEndpointView ep) {
    final chips = <Widget>[];

    void addChip(int count, WebhookDeliveryStatusView status) {
      if (count > 0) {
        chips.add(_statusChip(count, status));
      }
    }

    addChip(ep.pendingCount, WebhookDeliveryStatusView.pending);
    addChip(ep.deliveringCount, WebhookDeliveryStatusView.delivering);
    addChip(ep.failedCount, WebhookDeliveryStatusView.failed);
    addChip(ep.deadCount, WebhookDeliveryStatusView.dead);

    // 100% success: success chip OR if any successes alongside errors
    if (ep.successCount > 0) {
      addChip(ep.successCount, WebhookDeliveryStatusView.success);
    }

    // Endpoint 100% saudável (só sucesso, sem outros): badge OK
    final allGreen =
        ep.pendingCount == 0 &&
        ep.deliveringCount == 0 &&
        ep.failedCount == 0 &&
        ep.deadCount == 0 &&
        ep.successCount > 0;
    if (allGreen) {
      return const Wrap(
        spacing: 4,
        children: [
          VeraProbChip(
            label: 'OK',
            color: VeraProbColors.success,
            icon: Icons.check_circle_outline,
          ),
        ],
      );
    }

    if (chips.isEmpty) return null;
    return Wrap(spacing: 4, children: chips);
  }

  Widget _statusChip(int count, WebhookDeliveryStatusView status) {
    final color = switch (status) {
      WebhookDeliveryStatusView.success => VeraProbColors.success,
      WebhookDeliveryStatusView.failed ||
      WebhookDeliveryStatusView.dead => VeraProbColors.error,
      WebhookDeliveryStatusView.pending ||
      WebhookDeliveryStatusView.delivering => VeraProbColors.warning,
    };

    return VeraProbChip(label: '$count ${status.labelPt}', color: color);
  }
}
