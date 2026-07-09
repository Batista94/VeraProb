import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/legal/legal_consent_status.dart'; // pr_scanner: ignore
import 'package:veraprob/domain/legal/legal_document.dart'; // pr_scanner: ignore

import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/legal_consent_providers.dart';

/// Full-screen LGPD Legal Gate — blocks shells until terms are accepted.
class LegalConsentScreen extends ConsumerStatefulWidget {
  const LegalConsentScreen({super.key});

  @override
  ConsumerState<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends ConsumerState<LegalConsentScreen> {
  bool _acceptedCheckbox = false;
  bool _isSaving = false;

  Future<void> _onAccept(LegalDocument doc) async {
    if (_isSaving || !_acceptedCheckbox) return;
    setState(() => _isSaving = true);

    // WASM-CONTEXT-LEAK: capture messenger before await.
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(legalConsentRepositoryProvider).acceptTerms(doc.id);
      // Invalidation rebuilds status → app_router listen → ConsentRefreshNotifier.
      ref.invalidate(legalConsentStatusProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível registrar seu aceite. Tente novamente.',
          ),
        ),
      );
      return;
    }

    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _onDecline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: VeraProbColors.surface,
        title: const Text(
          'Recusar termos',
          style: TextStyle(color: VeraProbColors.textPrimary),
        ),
        content: const Text(
          'Ao recusar, você será desconectado e não poderá usar o sistema. '
          'Deseja continuar?',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.error,
              foregroundColor: VeraProbColors.background,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Recusar e sair'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    // Navigation owned by AuthRefreshNotifier → router bounce to /login.
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final asyncStatus = ref.watch(legalConsentStatusProvider);

    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: asyncStatus.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _buildErrorBody(),
        data: (status) {
          final doc = status.document;
          if (doc == null) {
            return _buildErrorBody();
          }
          return _buildGate(status, doc);
        },
      ),
    );
  }

  Widget _buildErrorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Não foi possível carregar os Termos de Uso.',
              style: TextStyle(color: VeraProbColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(legalConsentStatusProvider),
              child: const Text('Tentar novamente'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _onDecline, child: const Text('Sair')),
          ],
        ),
      ),
    );
  }

  Widget _buildGate(LegalConsentStatus status, LegalDocument doc) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final published = dateFmt.format(doc.publishedAtUtc.toLocal());
    final hashShort = doc.contentSha256.length >= 12
        ? doc.contentSha256.substring(0, 12)
        : doc.contentSha256;
    final showChangelog =
        status.priorVersion != null &&
        (doc.changelog != null && doc.changelog!.trim().isNotEmpty);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                _buildHeader(doc, published, hashShort),
                if (showChangelog) ...[
                  const SizedBox(height: 12),
                  _buildChangelogCallout(doc.changelog!),
                ],
                const SizedBox(height: 12),
                Expanded(child: _buildReader(doc)),
                const SizedBox(height: 12),
                _buildFooter(doc),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LegalDocument doc, String published, String hashShort) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          doc.title,
          style: VeraProbTypography.heading.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: VeraProbColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text(
                'Versão ${doc.version} — publicada em $published',
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: VeraProbColors.surfaceElevated,
              side: BorderSide.none,
            ),
            Tooltip(
              message: doc.contentSha256,
              child: Chip(
                label: Text(
                  'SHA $hashShort…',
                  style: VeraProbTypography.mono(size: 11),
                ),
                backgroundColor: VeraProbColors.surfaceElevated,
                side: BorderSide.none,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: doc.bodyMarkdown));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Texto dos termos copiado para a área de transferência.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Baixar / copiar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChangelogCallout(String changelog) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: VeraProbColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'O que mudou nesta versão',
            style: TextStyle(
              color: VeraProbColors.warning,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            changelog,
            style: const TextStyle(
              color: VeraProbColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReader(LegalDocument doc) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            doc.bodyMarkdown,
            style: const TextStyle(
              color: VeraProbColors.textPrimary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(LegalDocument doc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: _acceptedCheckbox,
          onChanged: _isSaving
              ? null
              : (v) => setState(() => _acceptedCheckbox = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Li e aceito os Termos de Uso e o contrato de custódia de dados, '
            'e estou ciente do tratamento de dados pessoais conforme a LGPD '
            '(Lei 13.709/2018).',
            style: TextStyle(color: VeraProbColors.textPrimary, fontSize: 13),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSaving ? null : _onDecline,
                child: const Text('Recusar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: VeraProbColors.primary,
                  foregroundColor: VeraProbColors.background,
                ),
                onPressed: (!_acceptedCheckbox || _isSaving)
                    ? null
                    : () => _onAccept(doc),
                child: _isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Aceitar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
