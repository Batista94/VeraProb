// forensic_log_view.dart
//
// P2 redesign: structured metadata card + HMAC masked by default + payload
// collapsed by default.
//
// WASM-CONTEXT-LEAK: ScaffoldMessenger captured before await (unchanged).
// _MonoJsonView and _SanitizedText left intact (security-critical sanitization).
// Replay button behaviour unchanged (debounce 3s, typed exceptions).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_log_view.dart';
import 'package:veraprob/application/webhooks/webhook_delivery_status_view.dart';
import 'package:veraprob/application/webhooks/webhook_exceptions.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/hash_text.dart';
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
      padding: const EdgeInsets.all(VeraProbSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetadataCard(),
          const SizedBox(height: VeraProbSpacing.md),
          _buildPayloadSection(),
          if (widget.log.lastError != null) ...[
            const SizedBox(height: VeraProbSpacing.md),
            _buildErrorSection(),
          ],
          if (widget.log.status == WebhookDeliveryStatusView.failed ||
              widget.log.status == WebhookDeliveryStatusView.dead)
            _buildReplayButton(),
        ],
      ),
    );
  }

  // ── Metadata card ─────────────────────────────────────────────────────────

  Widget _buildMetadataCard() {
    return Card(
      color: VeraProbColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: VeraProbRadii.smAll),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(VeraProbSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _metaRow('Event ID', widget.log.id, masked: false),
            const SizedBox(height: VeraProbSpacing.sm),
            _metaRow(
              'Ledger Entry ID',
              widget.log.ledgerEntryId,
              masked: false,
            ),
            if (widget.log.signature != null) ...[
              const SizedBox(height: VeraProbSpacing.sm),
              _metaRow('Signature (HMAC)', widget.log.signature!, masked: true),
            ],
            if (widget.log.dispatchedAt != null) ...[
              const SizedBox(height: VeraProbSpacing.sm),
              _attemptRow(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value, {required bool masked}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: HashText(value: value, masked: masked, showCopyButton: true),
        ),
      ],
    );
  }

  Widget _attemptRow() {
    final dispatched = widget.log.dispatchedAt!;
    final formatted =
        '${dispatched.day.toString().padLeft(2, '0')}/'
        '${dispatched.month.toString().padLeft(2, '0')}/'
        '${dispatched.year} '
        '${dispatched.hour.toString().padLeft(2, '0')}:'
        '${dispatched.minute.toString().padLeft(2, '0')} UTC';

    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            'Tentativa',
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${widget.log.attemptCount} · despachado em $formatted',
            style: VeraProbTypography.mono.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ── Payload section ───────────────────────────────────────────────────────

  Widget _buildPayloadSection() {
    return ExpansionTile(
      title: const Text(
        'Payload enviado',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: VeraProbSpacing.sm),
      children: [_MonoJsonView(widget.log.payload)],
    );
  }

  // ── Error section ─────────────────────────────────────────────────────────

  Widget _buildErrorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Erro retornado',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: VeraProbColors.error,
          ),
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        _SanitizedText(widget.log.lastError!),
      ],
    );
  }

  // ── Replay button (behaviour unchanged) ───────────────────────────────────

  Widget _buildReplayButton() {
    return Padding(
      padding: const EdgeInsets.only(top: VeraProbSpacing.md),
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

// ── Sanitized JSON view (security-critical — DO NOT modify sanitization) ─────

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
      padding: const EdgeInsets.all(VeraProbSpacing.sm),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.smAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: SelectableText(
        sanitized,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

// ── Sanitized error text (security-critical — DO NOT modify sanitization) ────

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
      padding: const EdgeInsets.all(VeraProbSpacing.sm),
      decoration: BoxDecoration(
        color: VeraProbColors.error.withValues(alpha: 0.05),
        borderRadius: VeraProbRadii.smAll,
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
