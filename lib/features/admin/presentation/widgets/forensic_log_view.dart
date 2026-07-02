import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/application/webhooks/webhook_exceptions.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/webhook_providers.dart';

class ForensicLogView extends ConsumerStatefulWidget {
  final WebhookDeliveryLogView log;
  const ForensicLogView({super.key, required this.log});

  @override
  ConsumerState<ForensicLogView> createState() => _ForensicLogViewState();
}

class _ForensicLogViewState extends ConsumerState<ForensicLogView> {
  bool _isReplaying = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HashRow('Event ID', widget.log.id),
          _HashRow('Ledger Entry ID', widget.log.ledgerEntryId),
          if (widget.log.signature != null)
            _HashRow('Signature (HMAC)', widget.log.signature!),
          const SizedBox(height: 16),
          const Text(
            'Payload enviado',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _MonoJsonView(widget.log.payload),
          if (widget.log.lastError != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Erro retornado',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: VeraProbColors.error,
              ),
            ),
            const SizedBox(height: 8),
            _SanitizedText(widget.log.lastError!),
          ],
          if (widget.log.status == WebhookDeliveryStatusView.failed ||
              widget.log.status == WebhookDeliveryStatusView.dead)
            _buildReplayButton(),
        ],
      ),
    );
  }

  Widget _buildReplayButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: _isReplaying ? null : _handleReplay,
          icon: _isReplaying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: const Text('Replay Manual'),
        ),
      ),
    );
  }

  Future<void> _handleReplay() async {
    setState(() {
      _isReplaying = true;
    });

    // Captura ScaffoldMessenger antes do await (WASM-CONTEXT-LEAK)
    final messenger = ScaffoldMessenger.of(context);

    try {
      final repo = ref.read(webhookRepositoryProvider);

      // Debounce punitivo de mínimo 3 segundos (Anti-DDoS)
      await Future.wait<void>([
        repo.manualReplay(widget.log.id),
        Future<void>.delayed(const Duration(seconds: 3)),
      ]);

      messenger.showSnackBar(
        const SnackBar(content: Text('Replay solicitado com sucesso.')),
      );
    } on WebhookApplicationException catch (e) {
      // Mensagem já traduzida para vocabulário de domínio (PT) na infra.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Erro inesperado ao solicitar o reprocessamento.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isReplaying = false;
        });
      }
    }
  }
}

class _HashRow extends StatelessWidget {
  final String label;
  final String value;
  const _HashRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: VeraProbColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonoJsonView extends StatelessWidget {
  final Map<String, dynamic> payload;
  const _MonoJsonView(this.payload);

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    // Remove control chars just in case (except \n, \t)
    final sanitized = pretty.replaceAll(
      RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]'),
      '',
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: SelectableText(
        sanitized,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

class _SanitizedText extends StatelessWidget {
  final String text;
  const _SanitizedText(this.text);

  @override
  Widget build(BuildContext context) {
    // Remove control chars (except \n, \t) to avoid invisible attacks
    final sanitized = text.replaceAll(
      RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]'),
      '',
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: VeraProbColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: VeraProbColors.error.withValues(alpha: 0.2)),
      ),
      child: SelectableText(
        sanitized,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: VeraProbColors.error,
        ),
      ),
    );
  }
}
