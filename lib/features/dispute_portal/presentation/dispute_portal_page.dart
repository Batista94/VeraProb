import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_submission_notifier.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

import 'package:veraprob/features/dispute_portal/presentation/widgets/portal_header.dart';
import 'package:veraprob/features/dispute_portal/presentation/widgets/dispute_context_card.dart';
import 'package:veraprob/features/dispute_portal/presentation/widgets/dispute_success_view.dart';
import 'package:veraprob/features/dispute_portal/presentation/widgets/evidence_dropzone.dart';
import 'package:veraprob/features/dispute_portal/presentation/widgets/dispute_action_footer.dart';

/// Public, tokenized dispute portal for an external carrier (no Supabase auth).
class DisputePortalPage extends ConsumerWidget {
  final String token;
  const DisputePortalPage({super.key, required this.token});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageDataAsync = ref.watch(portalPageDataProvider(token));

    return Scaffold(
      backgroundColor: VeraProbColors.background,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: pageDataAsync.when(
                data: (data) => _buildLoaded(context, ref, data),
                loading: () => const _LoadingView(),
                error: (err, _) {
                  String msg = 'Link inválido ou expirado.';
                  bool retryable = false;
                  if (err is PortalDisputeException) {
                    msg = err.message;
                    retryable = err.retryable;
                  }
                  return _ErrorView(
                    message: msg,
                    retryable: retryable,
                    onRetry: () =>
                        ref.invalidate(portalPageDataProvider(token)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    WidgetRef ref,
    PortalPageData data,
  ) {
    // Verdict sealed internally: the defense window is closed and the token was
    // revoked in the same transaction. Block any phantom submission attempt.
    if (data.snapshot.closedInternally) {
      return const _PortalCard(
        icon: Icons.gavel_outlined,
        color: VeraProbColors.textSecondary,
        title: 'SLA encerrado',
        message:
            'Sanção julgada internamente. O prazo de defesa foi finalizado.',
      );
    }

    final contextData = data.contextData!;
    final submissionState = ref.watch(portalDisputeSubmissionNotifierProvider);
    final notifier = ref.read(portalDisputeSubmissionNotifierProvider.notifier);

    // If successfully submitted this session:
    if (submissionState is PortalSubmissionSuccess) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortalHeader(
            orgDisplayName: contextData.orgDisplayName ?? 'Oculto',
            orgCnpj: contextData.orgCnpj ?? 'Oculto',
          ),
          const SizedBox(height: VeraProbSpacing.lg),
          DisputeSuccessView(
            submittedAtUtc: submissionState.submittedAtUtc,
            protocol: submissionState.protocol,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortalHeader(
          orgDisplayName: contextData.orgDisplayName ?? 'Oculto',
          orgCnpj: contextData.orgCnpj ?? 'Oculto',
        ),
        const SizedBox(height: VeraProbSpacing.lg),
        DisputeContextCard(contextData: contextData),
        const SizedBox(height: VeraProbSpacing.lg),

        if (submissionState is PortalSubmissionRetrying)
          Container(
            margin: const EdgeInsets.only(bottom: VeraProbSpacing.lg),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VeraProbColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: VeraProbColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: VeraProbColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Serviço instável. Reenviando… '
                    '(tentativa ${submissionState.attempt} de '
                    '${submissionState.maxAttempts})',
                    style: VeraProbTypography.bodyMedium.copyWith(
                      color: VeraProbColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (submissionState is PortalSubmissionError)
          Container(
            margin: const EdgeInsets.only(bottom: VeraProbSpacing.lg),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VeraProbColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: VeraProbColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: VeraProbColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    submissionState.errorMessage,
                    style: VeraProbTypography.bodyMedium.copyWith(
                      color: VeraProbColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (data.snapshot.isDisputed) ...[
          EvidenceDropzone(
            state: submissionState,
            onFileStaged: notifier.stageFile,
            onFileCleared: notifier.clearFile,
          ),
          const SizedBox(height: VeraProbSpacing.lg),
          DisputeActionFooter(
            state: submissionState,
            onJustificationChanged: notifier.setJustification,
            onSubmit: () => notifier.submit(token),
            onAcknowledge: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(portalDisputeGatewayProvider)
                    .acknowledge(
                      token: token,
                      snapshotHash: data.snapshot.snapshotHash,
                    );
                ref.invalidate(portalPageDataProvider(token));
              } on PortalDisputeException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
          ),
        ] else if (data.snapshot.isApplied) ...[
          const _PortalCard(
            icon: Icons.verified_outlined,
            color: VeraProbColors.success,
            title: 'Penalidade Aceita',
            message:
                'Seu aceite foi registrado de forma definitiva e auditável. Obrigado.',
          ),
        ],
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
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
}

class _ErrorView extends StatelessWidget {
  final String message;
  final bool retryable;
  final VoidCallback? onRetry;

  const _ErrorView({
    required this.message,
    this.retryable = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PortalCard(
          icon: Icons.error_outline,
          color: VeraProbColors.error,
          title: retryable ? 'Falha de Conexão' : 'Link Inválido',
          message: message,
        ),
        if (retryable && onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar Novamente'),
          ),
        ],
      ],
    );
  }
}

class _PortalCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _PortalCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 16),
          Text(
            title,
            style: VeraProbTypography.sectionTitle.copyWith(color: color),
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
