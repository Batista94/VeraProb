// RevealSecretModal — Reveal-Once modal blindado (Pilar 1).
//
// Regras de segurança (INV-28):
//   - barrierDismissible: false (ESC/backdrop bloqueados)
//   - Plaintext somente no webhookSecretRevealProvider (autoDispose)
//   - _close(): ref.invalidate() ANTES de Navigator.pop (belt-and-suspenders)
//   - WidgetsBindingObserver: lifecycle scrub ao perder foco do SO
//   - Sem SharedPreferences/Hive/disk
//   - ScaffoldMessenger capturado PRÉ-await (WASM-CONTEXT-LEAK)
//
// INV-13: importa apenas application layer (IWebhookRepository via provider).
// UX-RAW-EXCEPTION: nunca exibe $e. Mensagens em vocabulary de domínio.
// IIFE-UI-SMELL: lógica extraída em _buildX helpers.
// WASM-CONTEXT-LEAK: messenger capturado antes de qualquer await.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

/// Modal blindado Reveal-Once para exibição do segredo de assinatura HMAC.
///
/// Sempre aberto via showDialog(barrierDismissible: false).
/// Nunca exibe o segredo novamente após fechar (rotate se perdido).
class RevealSecretModal extends ConsumerStatefulWidget {
  const RevealSecretModal({super.key});

  @override
  ConsumerState<RevealSecretModal> createState() => _RevealSecretModalState();
}

class _RevealSecretModalState extends ConsumerState<RevealSecretModal>
    with WidgetsBindingObserver {
  bool _secretVisible = false;
  bool _stored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Lifecycle scrub: SO perdeu foco (minimizou, ligou tela, etc.).
  // Invalida o segredo da RAM imediatamente. Nenhum dado sensível persiste.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Anula referência ANTES de tentar fechar o modal.
      ref.invalidate(webhookSecretRevealProvider);
      Navigator.maybePop(context);
    }
  }

  void _close() {
    // belt-and-suspenders: invalida ANTES do pop (não depende do timing do autoDispose).
    ref.invalidate(webhookSecretRevealProvider);
    Navigator.pop(context);
  }

  Future<void> _copySecret(String secret) async {
    // WASM-CONTEXT-LEAK: captura messenger ANTES do await.
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: secret));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Segredo copiado para a área de transferência.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webhookSecretRevealProvider);

    return AlertDialog(
      title: _buildTitle(state),
      content: SizedBox(width: 480, child: _buildContent(state)),
      actions: [_buildCloseButton(state)],
    );
  }

  // ── Widget helpers (sem IIFE — IIFE-UI-SMELL) ─────────────────────────────

  Widget _buildTitle(RevealState state) {
    final version = state.version;
    return Row(
      children: [
        const Icon(Icons.key, size: 20, color: VeraProbColors.warning),
        const SizedBox(width: 8),
        Text(
          version != null
              ? 'Segredo de Assinatura · v$version'
              : 'Segredo de Assinatura',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildContent(RevealState state) {
    if (state.loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return _buildErrorView(state.error!);
    }

    if (state.secretHex != null) {
      return _buildRevealView(state.secretHex!);
    }

    // Estado inicial — nunca deve ser visto em uso normal
    // (modal só é aberto após provision/rotate bem-sucedido).
    return const SizedBox(
      height: 80,
      child: Center(
        child: Text(
          'Nenhum segredo para exibir.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildRevealView(String secret) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWarningBanner(),
        const SizedBox(height: 16),
        _buildSecretField(secret),
        const SizedBox(height: 16),
        _buildStoredCheckbox(),
      ],
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.warning),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 18, color: VeraProbColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Exibido UMA ÚNICA VEZ. Caso perca este segredo, '
              'será necessário realizar uma rotação forçada para obter um novo.',
              style: TextStyle(
                color: VeraProbColors.warning,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecretField(String secret) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chave HMAC-SHA256 (hex)',
          style: TextStyle(
            fontSize: 11,
            color: VeraProbColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: VeraProbColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: VeraProbColors.border),
          ),
          child: Stack(
            children: [
              SelectableText(
                secret,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              // Blur overlay quando segredo não foi explicitamente revelado.
              if (!_secretVisible)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _secretVisible = true),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        color: VeraProbColors.surface.withValues(alpha: 0.95),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.visibility,
                              size: 16,
                              color: VeraProbColors.textSecondary,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Toque para revelar',
                              style: TextStyle(
                                color: VeraProbColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _copySecret(secret),
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copiar chave', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildStoredCheckbox() {
    return CheckboxListTile(
      value: _stored,
      onChanged: (v) => setState(() => _stored = v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Confirmo que armazenei esta chave com segurança. '
        'Compreendo que ela nunca mais será exibida.',
        style: TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildErrorView(String errorMessage) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: VeraProbColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: const TextStyle(color: VeraProbColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton(RevealState state) {
    final hasSecret = state.secretHex != null;
    // Gate obrigatório: só fecha se (a) não há segredo ou (b) checkbox marcado.
    final canClose = !hasSecret || _stored;

    return FilledButton(
      onPressed: canClose ? _close : null,
      child: const Text('Concluir'),
    );
  }
}
