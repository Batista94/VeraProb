import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/super_admin/generate_org_secret_handler.dart';
import 'package:veraprob/application/super_admin/org_api_secret_view_model.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

/// Widget for managing per-org HMAC secrets (INV-28).
///
/// Displays the current secret version and provides a button to generate
/// a new secret. The plain-text secret is shown ONCE after generation.
///
/// **INV-4 / Lens 2:** The [currentSecret] parameter uses
/// [OrgApiSecretViewModel] (application layer) instead of [OrgApiSecret]
/// (domain). All fields are primitives — no domain logic in the widget.
class OrgSecretCard extends ConsumerStatefulWidget {
  final String organizationId;
  final String organizationName;
  final OrgApiSecretViewModel? currentSecret;

  const OrgSecretCard({
    super.key,
    required this.organizationId,
    required this.organizationName,
    this.currentSecret,
  });

  @override
  ConsumerState<OrgSecretCard> createState() => _OrgSecretCardState();
}

class _OrgSecretCardState extends ConsumerState<OrgSecretCard> {
  bool _isGenerating = false;
  String? _generatedSecret;
  String? _errorMessage;

  Future<void> _generateSecret() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gerar Novo Secret'),
        content: Text(
          widget.currentSecret != null
              ? 'O secret atual (v${widget.currentSecret!.version}) será revogado. '
                    'O novo secret será exibido UMA ÚNICA VEZ. '
                    'Certifique-se de copiá-lo antes de fechar este diálogo.'
              : 'Um novo secret HMAC será gerado para ${widget.organizationName}. '
                    'O secret será exibido UMA ÚNICA VEZ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.error,
            ),
            child: const Text('Gerar Secret'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _generatedSecret = null;
    });

    try {
      final handler = ref.read(generateOrgSecretHandlerProvider);
      final result = await handler.handle(
        organizationId: widget.organizationId,
        sessionId: 'super-admin-session', // SuperAdmin cross-tenant
      );

      if (!mounted) return;
      setState(() {
        _generatedSecret = result.secret;
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (e) {
          OrgSecretException(:final message) => message,
          _ => 'Falha ao gerar secret. Tente novamente.',
        };
        _isGenerating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.key,
                  size: 20,
                  color: VeraProbColors.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'HMAC Secret (INV-28)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.currentSecret != null) ...[
              _InfoRow('Versão', 'v${widget.currentSecret!.version}'),
              _InfoRow(
                'Criado em',
                _formatDate(widget.currentSecret!.createdAt),
              ),
              if (widget.currentSecret!.rotatedAt != null)
                _InfoRow(
                  'Rotacionado em',
                  _formatDate(widget.currentSecret!.rotatedAt!),
                ),
            ] else
              const Text(
                'Nenhum secret configurado.',
                style: TextStyle(
                  color: VeraProbColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 12),
            if (_generatedSecret != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: VeraProbColors.warning.withValues(alpha: 0.1),
                  borderRadius: VeraProbRadii.mdAll,
                  border: Border.all(color: VeraProbColors.warning),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: VeraProbColors.warning,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Copie agora — não será exibido novamente!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: VeraProbColors.warning,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _generatedSecret!,
                            style: VeraProbTypography.mono(size: 11),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copiar',
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await Clipboard.setData(
                              ClipboardData(text: _generatedSecret!),
                            );
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Secret copiado!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: VeraProbColors.error,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _isGenerating ? null : _generateSecret,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(
                widget.currentSecret != null
                    ? 'Rotacionar Secret'
                    : 'Gerar Secret',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
          Text(value, style: VeraProbTypography.mono(size: 12)),
        ],
      ),
    );
  }
}
