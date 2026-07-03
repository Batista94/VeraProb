// webhook_management_screen.dart
//
// Composition root for the Webhook Management feature (P2 redesign).
//
// Kills double-chrome: no local Scaffold/AppBar. Consumes shell Scaffold.
// VeraProbHeader + MasterDetailScaffold + EndpointListPanel + DeliveryLogPanel.
//
// UAT-frozen label: 'Configurações de Integração (Webhooks)' (never rename
// without updating UAT doc + tests in same diff).
// UAT-frozen CTA: 'Novo Endpoint'.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/reveal_secret_modal.dart';
import 'package:veraprob/features/admin/presentation/widgets/create_endpoint_dialog.dart';
import 'package:veraprob/features/admin/presentation/widgets/webhook/endpoint_list_panel.dart';
import 'package:veraprob/features/admin/presentation/widgets/webhook/delivery_log_panel.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

class WebhookManagementScreen extends ConsumerWidget {
  const WebhookManagementScreen({super.key});

  // ── Flows (single SSOT — panel empty-state CTA delegates here) ────────────

  Future<void> _createEndpointFlow(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const CreateEndpointDialog(),
    );
    if (created != true || !context.mounted) return;
    await _showRevealModal(context, RevealAction.provision);
  }

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
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: true,
      builder: (_) => RevealSecretModal(action: action),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedEndpointIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(VeraProbSpacing.md),
          child: VeraProbHeader(
            icon: Icons.webhook,
            title: 'Configurações de Integração (Webhooks)',
            actions: [
              Tooltip(
                message:
                    'Rotacionar segredo de assinatura (afeta todos os endpoints)',
                child: IconButton(
                  icon: const Icon(Icons.autorenew, size: 20),
                  onPressed: () => _rotateSecretFlow(context),
                ),
              ),
              const SizedBox(width: VeraProbSpacing.xs),
              FilledButton.icon(
                onPressed: () => _createEndpointFlow(context),
                icon: const Icon(Icons.add),
                label: const Text('Novo Endpoint'),
              ),
            ],
          ),
        ),
        Expanded(
          child: MasterDetailScaffold(
            masterBuilder: (_) => EndpointListPanel(
              onCreateEndpoint: () => _createEndpointFlow(context),
            ),
            detailBuilder: (_) => const DeliveryLogPanel(),
            hasSelection: selectedId != null,
            onBack: () =>
                ref.read(selectedEndpointIdProvider.notifier).select(null),
          ),
        ),
      ],
    );
  }
}
