import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/features/admin/presentation/screens/justification_submission_form.dart';

/// Public page for driver self-service justification submission.
///
/// Reached via `/?justify=true&token=<uuid>` — no Supabase auth required.
/// Token validity is the sole authorization gate (PO-1).
///
/// Flow:
///   1. Page loads → validates token via [JustificationRepository.findToken].
///   2. Invalid/expired/used → shows error card (same pattern as ReviewContractScreen).
///   3. Valid + unused → shows [JustificationSubmissionForm(token: token)].
class DriverJustificationPage extends ConsumerStatefulWidget {
  final String token;

  const DriverJustificationPage({super.key, required this.token});

  @override
  ConsumerState<DriverJustificationPage> createState() =>
      _DriverJustificationPageState();
}

class _DriverJustificationPageState
    extends ConsumerState<DriverJustificationPage> {
  JustificationSubmissionToken? _tokenEntity;
  bool _loading = true;
  bool _submitted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _validateToken();
  }

  Future<void> _validateToken() async {
    try {
      final repo = ref.read(justificationRepositoryProvider);
      final entity = await repo.findToken(widget.token);

      if (!mounted) return;

      if (entity == null) {
        setState(() {
          _loading = false;
          _errorMessage = 'Link inválido ou não encontrado.';
        });
        return;
      }

      if (!entity.isActive) {
        setState(() {
          _loading = false;
          _errorMessage = entity.usedAtUtc != null
              ? 'Este link já foi utilizado e não pode ser reaproveitado.'
              : 'Este link expirou. Solicite um novo link ao operador.';
        });
        return;
      }

      setState(() {
        _loading = false;
        _tokenEntity = entity;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Erro ao validar o link. Tente novamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Validando link...',
            style: TextStyle(color: VeraProbColors.textSecondary),
          ),
        ],
      );
    }

    if (_submitted) {
      return _SuccessCard();
    }

    if (_errorMessage != null) {
      return _ErrorCard(message: _errorMessage!);
    }

    if (_tokenEntity != null) {
      return _TokenFormWrapper(
        token: _tokenEntity!,
        onSubmitted: () => setState(() => _submitted = true),
      );
    }

    return const SizedBox.shrink();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _TokenFormWrapper extends StatelessWidget {
  final JustificationSubmissionToken token;
  final VoidCallback onSubmitted;

  const _TokenFormWrapper({required this.token, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: VeraProbColors.primary),
            const SizedBox(width: 12),
            Text(
              'Defesa de Ocorrência',
              style: VeraProbTypography.sectionTitle,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Preencha os campos abaixo para contestar a ocorrência registrada. '
          'Sua justificativa será analisada pela equipe responsável.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
        const SizedBox(height: 24),
        // Embed the form inline (not as a dialog) for the driver page
        _InlineSubmissionForm(token: token, onSubmitted: onSubmitted),
      ],
    );
  }
}

/// Inline (non-dialog) variant of [JustificationSubmissionForm] for the driver page.
///
/// Shares the same implementation but renders directly in the page scaffold
/// instead of a Dialog container.
class _InlineSubmissionForm extends ConsumerWidget {
  final JustificationSubmissionToken token;
  final VoidCallback onSubmitted;

  const _InlineSubmissionForm({required this.token, required this.onSubmitted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Delegate to the standard form — it handles the token path internally.
    // We show it as a dialog so we can intercept the Navigator.pop() result.
    return JustificationSubmissionForm(
      token: token,
      contractId: token.contractId,
      setId: token.setId,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VeraProbColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: VeraProbColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Link Inválido',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VeraProbColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: VeraProbColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 48,
            color: VeraProbColors.success,
          ),
          const SizedBox(height: 16),
          Text(
            'Justificativa Enviada',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.success,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sua contestação foi registrada com sucesso e será analisada '
            'pela equipe responsável em breve.',
            textAlign: TextAlign.center,
            style: TextStyle(color: VeraProbColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
