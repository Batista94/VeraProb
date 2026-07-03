// CreateEndpointDialog — provisiona um novo webhook endpoint (Pilar 1).
//
// Fluxo: valida URL HTTPS → insert via IWebhookRepository (RLS TENANT_ADMIN)
// → invalida health provider → retorna true para o caller abrir o
// RevealSecretModal (provision).
//
// WASM-CONTEXT-LEAK: navigator/messenger capturados PRÉ-await.
// UX-RAW-EXCEPTION: apenas mensagens de domínio em PT.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/webhooks/webhook_exceptions.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

/// Dialog de criação de endpoint. `Navigator.pop(true)` em caso de sucesso.
class CreateEndpointDialog extends ConsumerStatefulWidget {
  const CreateEndpointDialog({super.key});

  @override
  ConsumerState<CreateEndpointDialog> createState() =>
      _CreateEndpointDialogState();
}

class _CreateEndpointDialogState extends ConsumerState<CreateEndpointDialog> {
  final _urlController = TextEditingController();
  String? _validationError;
  bool _isSaving = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (!url.startsWith('https://') || Uri.tryParse(url) == null) {
      setState(() {
        _validationError = 'Informe uma URL válida iniciando com https://';
      });
      return;
    }

    final orgId = ref.read(currentOrganizationIdProvider);
    if (orgId == null) {
      setState(() {
        _validationError =
            'Sessão sem organização ativa. Autentique-se novamente.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });

    // WASM-CONTEXT-LEAK: captura ANTES do await.
    final navigator = Navigator.of(context);

    try {
      await ref.read(webhookRepositoryProvider).createEndpoint(orgId, url);
      ref.invalidate(webhookEndpointHealthProvider);
      navigator.pop(true);
    } on WebhookApplicationException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _validationError = e.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _validationError =
            'Não foi possível criar o endpoint. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo Endpoint de Webhook'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Os vereditos selados serão entregues via POST assinado '
              '(HMAC-SHA256) para esta URL.',
              style: VeraProbTypography.bodySmall.copyWith(
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: VeraProbSpacing.md),
            TextField(
              key: const ValueKey('create-endpoint-url-field'),
              controller: _urlController,
              enabled: !_isSaving,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'URL do endpoint (HTTPS)',
                hintText: 'https://erp.suaempresa.com.br/webhooks/veraprob',
                errorText: _validationError,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _isSaving ? null : _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Criar Endpoint'),
        ),
      ],
    );
  }
}
