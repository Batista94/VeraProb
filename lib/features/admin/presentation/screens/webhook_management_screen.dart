import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/application/webhooks/webhook_endpoint_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';
import 'package:veraprob/features/admin/presentation/widgets/create_endpoint_dialog.dart';
import 'package:veraprob/features/admin/presentation/widgets/forensic_log_view.dart';
import 'package:veraprob/features/admin/presentation/widgets/reveal_secret_modal.dart';

class WebhookManagementScreen extends ConsumerStatefulWidget {
  const WebhookManagementScreen({super.key});

  @override
  ConsumerState<WebhookManagementScreen> createState() =>
      _WebhookManagementScreenState();
}

class _WebhookManagementScreenState
    extends ConsumerState<WebhookManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Webhook Endpoints')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth <= 900;
          if (isNarrow) {
            return _buildStackLayout();
          }
          return _buildSplitLayout();
        },
      ),
    );
  }

  Widget _buildStackLayout() {
    final selectedId = ref.watch(selectedEndpointIdProvider);
    if (selectedId == null) {
      return const _EndpointListPanel();
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                ref.read(selectedEndpointIdProvider.notifier).select(null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Voltar'),
          ),
        ),
        const Expanded(child: _DeliveryLogPanel()),
      ],
    );
  }

  Widget _buildSplitLayout() {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 360, child: _EndpointListPanel()),
        VerticalDivider(width: 1),
        Expanded(child: _DeliveryLogPanel()),
      ],
    );
  }
}

class _EndpointListPanel extends ConsumerWidget {
  const _EndpointListPanel();

  /// Novo endpoint → (sucesso) → Reveal-Once do segredo (provision).
  Future<void> _createEndpointFlow(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreateEndpointDialog(),
    );
    if (created != true || !context.mounted) return;
    await _showRevealModal(context, RevealAction.provision);
  }

  /// Rotação explícita: confirmação (afeta TODOS os endpoints) → Reveal-Once.
  Future<void> _rotateSecretFlow(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rotacionar segredo de assinatura?'),
        content: const Text(
          'Uma nova chave (version+1) será gerada para TODOS os endpoints '
          'desta organização. A chave atual continuará válida por 30 minutos '
          'para entregas em trânsito. O ERP deverá ser atualizado com a nova '
          'chave, exibida uma única vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rotacionar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _showRevealModal(context, RevealAction.rotate);
  }

  Future<void> _showRevealModal(
    BuildContext context,
    RevealAction action,
  ) async {
    // Blindado: sem ESC/backdrop (plano Pilar 1).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (_) => RevealSecretModal(action: action),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpointsAsync = ref.watch(webhookEndpointHealthProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Tooltip(
                  message: 'Endpoints',
                  child: Text(
                    'Endpoints',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                tooltip:
                    'Rotacionar segredo de assinatura (afeta todos os endpoints)',
                icon: const Icon(Icons.autorenew, size: 20),
                onPressed: () => _rotateSecretFlow(context),
              ),
              Tooltip(
                message: 'Criar novo endpoint de webhook',
                child: FilledButton.icon(
                  onPressed: () => _createEndpointFlow(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Novo'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: endpointsAsync.when(
            data: (endpoints) => _buildList(endpoints, ref),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) => const Center(
              child: Text('Falha ao carregar endpoints'),
            ), // UX-RAW-EXCEPTION fix
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<WebhookEndpointView> endpoints, WidgetRef ref) {
    if (endpoints.isEmpty) {
      return const Center(child: Text('Nenhum endpoint configurado.'));
    }
    final selectedId = ref.watch(selectedEndpointIdProvider);

    return ListView.builder(
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final ep = endpoints[index];
        final isSelected = ep.id == selectedId;
        return ListTile(
          selected: isSelected,
          title: SelectableText(
            ep.url,
            style: const TextStyle(fontFamily: 'monospace'),
            maxLines: 1,
          ),
          subtitle: Wrap(
            spacing: 4,
            children: [
              if (ep.pendingCount > 0)
                _StatusChip(WebhookDeliveryStatusView.pending, ep.pendingCount),
              if (ep.deliveringCount > 0)
                _StatusChip(
                  WebhookDeliveryStatusView.delivering,
                  ep.deliveringCount,
                ),
              if (ep.failedCount > 0)
                _StatusChip(WebhookDeliveryStatusView.failed, ep.failedCount),
              if (ep.deadCount > 0)
                _StatusChip(WebhookDeliveryStatusView.dead, ep.deadCount),
              if (ep.successCount > 0)
                _StatusChip(WebhookDeliveryStatusView.success, ep.successCount),
            ],
          ),
          onTap: () =>
              ref.read(selectedEndpointIdProvider.notifier).select(ep.id),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final WebhookDeliveryStatusView status;
  final int count;
  const _StatusChip(this.status, this.count);

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case WebhookDeliveryStatusView.success:
        color = VeraProbColors.success;
        break;
      case WebhookDeliveryStatusView.failed:
      case WebhookDeliveryStatusView.dead:
        color = VeraProbColors.error;
        break;
      case WebhookDeliveryStatusView.pending:
      case WebhookDeliveryStatusView.delivering:
        color = VeraProbColors.warning;
        break;
    }
    return Chip(
      label: Text(
        '$count ${status.labelPt}',
        style: const TextStyle(fontSize: 10),
      ),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DeliveryLogPanel extends ConsumerWidget {
  const _DeliveryLogPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedEndpointIdProvider);
    if (selectedId == null) {
      return const Center(
        child: Text('Selecione um endpoint para ver os logs.'),
      );
    }

    final logsAsync = ref.watch(deliveryLogStreamProvider(selectedId));
    final filter = ref.watch(deliveryLogFilterProvider);

    return Column(
      children: [
        _buildFilterBar(ref, filter),
        const Divider(height: 1),
        Expanded(
          child: logsAsync.when(
            data: (logs) => _buildLogList(logs, filter),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) => const Center(
              child: Text('Falha ao carregar logs'),
            ), // UX-RAW-EXCEPTION fix
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    WidgetRef ref,
    WebhookDeliveryStatusView? currentFilter,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: currentFilter == null,
            onSelected: (val) =>
                ref.read(deliveryLogFilterProvider.notifier).setFilter(null),
          ),
          const SizedBox(width: 8),
          ...WebhookDeliveryStatusView.values.map((status) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(status.labelPt.toUpperCase()),
                selected: currentFilter == status,
                onSelected: (val) => ref
                    .read(deliveryLogFilterProvider.notifier)
                    .setFilter(val ? status : null),
              ),
            );
          }),
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
      return const Center(child: Text('Nenhum log encontrado.'));
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final log = filtered[index];
        return ExpansionTile(
          title: Row(
            children: [
              _StatusChip(log.status, log.attemptCount),
              const SizedBox(width: 8),
              Text(
                log.eventType,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          subtitle: Text(
            '${log.createdAt.toLocal()} · ${log.id.split('-').first}',
          ),
          children: [ForensicLogView(log: log)],
        );
      },
    );
  }
}
