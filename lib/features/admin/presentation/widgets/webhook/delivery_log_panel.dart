// delivery_log_panel.dart
//
// Detail panel for WebhookManagementScreen.
// Extracted from the monolithic webhook_management_screen.dart (P2 redesign).
//
// Header: URL do endpoint selecionado (HashText) + resumo de contagens.
// Filter chips: labels de labelPt INALTERADOS (freeze UAT).
// Empty states via shared EmptyState widget.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/forensic_log_view.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

/// Detail panel: delivery log for the selected webhook endpoint.
class DeliveryLogPanel extends ConsumerWidget {
  const DeliveryLogPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedEndpointIdProvider);
    if (selectedId == null) {
      return const EmptyState(
        icon: Icons.list_alt_outlined,
        title: 'Selecione um endpoint',
        description:
            'Escolha um endpoint na lista para visualizar os logs de entrega.',
      );
    }

    final endpointsAsync = ref.watch(webhookEndpointHealthProvider);
    final logsAsync = ref.watch(deliveryLogStreamProvider(selectedId));
    final filter = ref.watch(deliveryLogFilterProvider);

    // Selected endpoint for header context
    final selectedEndpoint = endpointsAsync.asData?.value
        .where((e) => e.id == selectedId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDetailHeader(selectedEndpoint),
        const Divider(height: 1),
        _buildFilterBar(ref, filter),
        const Divider(height: 1),
        Expanded(
          child: logsAsync.when(
            data: (logs) => _buildLogList(logs, filter),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) =>
                const Center(child: Text('Falha ao carregar logs')),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailHeader(WebhookEndpointView? endpoint) {
    if (endpoint == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(VeraProbSpacing.md),
      child: Row(
        children: [
          Expanded(child: HashText(value: endpoint.url, showCopyButton: true)),
          const SizedBox(width: VeraProbSpacing.sm),
          _buildCountSummary(endpoint),
        ],
      ),
    );
  }

  Widget _buildCountSummary(WebhookEndpointView ep) {
    final chips = <Widget>[];

    void maybeChip(int count, WebhookDeliveryStatusView status) {
      if (count > 0) {
        final color = switch (status) {
          WebhookDeliveryStatusView.success => VeraProbColors.success,
          WebhookDeliveryStatusView.failed ||
          WebhookDeliveryStatusView.dead => VeraProbColors.error,
          WebhookDeliveryStatusView.pending ||
          WebhookDeliveryStatusView.delivering => VeraProbColors.warning,
        };
        chips.add(
          VeraProbChip(label: '$count ${status.labelPt}', color: color),
        );
      }
    }

    maybeChip(ep.pendingCount, WebhookDeliveryStatusView.pending);
    maybeChip(ep.deliveringCount, WebhookDeliveryStatusView.delivering);
    maybeChip(ep.failedCount, WebhookDeliveryStatusView.failed);
    maybeChip(ep.deadCount, WebhookDeliveryStatusView.dead);
    maybeChip(ep.successCount, WebhookDeliveryStatusView.success);

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _buildFilterBar(
    WidgetRef ref,
    WebhookDeliveryStatusView? currentFilter,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(VeraProbSpacing.sm),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: currentFilter == null,
            onSelected: (_) =>
                ref.read(deliveryLogFilterProvider.notifier).setFilter(null),
          ),
          const SizedBox(width: VeraProbSpacing.sm),
          ...WebhookDeliveryStatusView.values.map(
            (status) => Padding(
              padding: const EdgeInsets.only(right: VeraProbSpacing.sm),
              child: ChoiceChip(
                label: Text(status.labelPt.toUpperCase()),
                selected: currentFilter == status,
                onSelected: (val) => ref
                    .read(deliveryLogFilterProvider.notifier)
                    .setFilter(val ? status : null),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(
    List<WebhookDeliveryLogView> logs,
    WebhookDeliveryStatusView? filter,
  ) {
    final filtered = filter == null
        ? logs
        : logs.where((l) => l.status == filter).toList();

    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_list_off,
        title: 'Nenhum log encontrado',
        description: 'Altere os filtros ou aguarde novas entregas.',
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final log = filtered[index];
        return ExpansionTile(
          title: Row(
            children: [
              _logStatusChip(log.status, log.attemptCount),
              const SizedBox(width: VeraProbSpacing.sm),
              Flexible(
                child: Text(
                  log.eventType,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            'Tentativa ${log.attemptCount} · ${log.id.substring(0, 8)}',
            style: VeraProbTypography.mono.copyWith(
              fontSize: 11,
              color: VeraProbColors.textSecondary,
            ),
          ),
          children: [ForensicLogView(log: log)],
        );
      },
    );
  }

  Widget _logStatusChip(WebhookDeliveryStatusView status, int count) {
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
