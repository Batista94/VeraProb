import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/application/dispute_portal/staged_file.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';

sealed class PortalSubmissionState {
  const PortalSubmissionState();
}

final class PortalSubmissionInitial extends PortalSubmissionState {
  const PortalSubmissionInitial();
}

final class PortalSubmissionStaging extends PortalSubmissionState {
  final String justification;
  final StagedFile? file;

  const PortalSubmissionStaging({required this.justification, this.file});

  bool get canSubmit => justification.trim().length >= 20;
}

final class PortalSubmissionHashing extends PortalSubmissionState {
  const PortalSubmissionHashing();
}

final class PortalSubmissionUploading extends PortalSubmissionState {
  const PortalSubmissionUploading();
}

/// Transient infra failure (edge-function 503) being retried with backoff.
final class PortalSubmissionRetrying extends PortalSubmissionState {
  final int attempt;
  final int maxAttempts;

  const PortalSubmissionRetrying({
    required this.attempt,
    required this.maxAttempts,
  });
}

final class PortalSubmissionSuccess extends PortalSubmissionState {
  final DateTime submittedAtUtc;
  final String protocol;

  const PortalSubmissionSuccess({
    required this.submittedAtUtc,
    required this.protocol,
  });
}

final class PortalSubmissionError extends PortalSubmissionState {
  final Exception cause;
  final PortalSubmissionStaging recoverable;

  const PortalSubmissionError(this.cause, this.recoverable);

  String get errorMessage {
    final e = cause;
    if (e is IntegrityException) return e.message;
    if (e is PortalDisputeException) return e.message;
    return 'Ocorreu um erro inesperado.';
  }
}

class PortalDisputeSubmissionNotifier extends Notifier<PortalSubmissionState> {
  static const List<String> _allowedExtensions = [
    '.pdf',
    '.jpg',
    '.jpeg',
    '.png',
  ];
  static const int _maxSizeBytes = 10 * 1024 * 1024; // 10MB

  bool _disposed = false;

  @override
  PortalSubmissionState build() {
    ref.onDispose(() => _disposed = true);
    return const PortalSubmissionInitial();
  }

  bool get _isBusy =>
      state is PortalSubmissionHashing ||
      state is PortalSubmissionUploading ||
      state is PortalSubmissionRetrying;

  void setJustification(String text) {
    if (_isBusy) {
      return; // Anti-duplo clique
    }

    final currentState = state;
    if (currentState is PortalSubmissionStaging) {
      state = PortalSubmissionStaging(
        justification: text,
        file: currentState.file,
      );
    } else if (currentState is PortalSubmissionError) {
      state = PortalSubmissionStaging(
        justification: text,
        file: currentState.recoverable.file,
      );
    } else {
      state = PortalSubmissionStaging(justification: text);
    }
  }

  void stageFile(StagedFile file) {
    if (_isBusy) {
      return;
    }

    if (file.sizeBytes > _maxSizeBytes) {
      throw const IntegrityException('O arquivo excede o limite de 10 MB.');
    }

    final hasAllowedExt = _allowedExtensions.any(
      (ext) => file.name.toLowerCase().endsWith(ext),
    );
    if (!hasAllowedExt) {
      throw const IntegrityException(
        'Formato de arquivo não suportado. Use PDF ou Imagem.',
      );
    }

    final currentState = state;
    if (currentState is PortalSubmissionStaging) {
      state = PortalSubmissionStaging(
        justification: currentState.justification,
        file: file,
      );
    } else if (currentState is PortalSubmissionError) {
      state = PortalSubmissionStaging(
        justification: currentState.recoverable.justification,
        file: file,
      );
    } else {
      state = PortalSubmissionStaging(justification: '', file: file);
    }
  }

  void clearFile() {
    if (_isBusy) {
      return;
    }

    final currentState = state;
    if (currentState is PortalSubmissionStaging) {
      state = PortalSubmissionStaging(
        justification: currentState.justification,
        file: null,
      );
    } else if (currentState is PortalSubmissionError) {
      state = PortalSubmissionStaging(
        justification: currentState.recoverable.justification,
        file: null,
      );
    }
  }

  bool _isSubmitting = false;

  Future<void> submit(String token) async {
    if (_isSubmitting) return;
    if (_isBusy) {
      return; // Guard anti-duplo-clique
    }

    final currentState = state;
    if (currentState is! PortalSubmissionStaging) {
      return;
    }

    if (!currentState.canSubmit) {
      state = PortalSubmissionError(
        const IntegrityException(
          'A justificativa deve ter no mínimo 20 caracteres.',
        ),
        currentState,
      );
      return;
    }

    _isSubmitting = true;
    try {
      String? sha256Client;
      final file = currentState.file;

      if (file != null) {
        state = const PortalSubmissionHashing();
        final hasher = ref.read(fileHasherProvider);
        sha256Client = await hasher.sha256Hex(file.bytes);
      }

      final gateway = ref.read(portalDisputeGatewayProvider);
      final policy = ref.read(portalRetryPolicyProvider);

      // Retry only genuine infra unavailability (PortalDisputeException.retryable,
      // i.e. edge-fn 503 / transient transport). A re-submit reuses the existing
      // QUARANTINE row by (token, sha256) — no extra slot consumed (idempotency,
      // migration 20260825000001). Business rejections (INV-26) are NOT retried.
      late final PortalSubmissionOutcome outcome;
      for (var attempt = 1; ; attempt++) {
        state = const PortalSubmissionUploading();
        try {
          outcome = await gateway.submitEvidence(
            token: token,
            justification: currentState.justification.trim(),
            file: file,
            sha256Client: sha256Client,
          );
          break;
        } on PortalDisputeException catch (e) {
          if (!e.retryable || attempt >= policy.maxAttempts) rethrow;
          state = PortalSubmissionRetrying(
            attempt: attempt,
            maxAttempts: policy.maxAttempts,
          );
          await Future<void>.delayed(policy.delayAfterAttempt(attempt));
          if (_disposed) return;
        }
      }

      // INV-9/INV-26: a 2xx transport is NOT a success — only the server's
      // verification verdict is. A rejected attachment (corrupt bytes, wrong
      // magic-byte signature, or hash drift) NEVER set defense_submitted_at, so
      // reporting success here would strand the dispute (the auditor card never
      // re-labels "DEFESA RECEBIDA") and silently bury the carrier's testimony.
      switch (outcome) {
        case PortalSubmissionOutcome.pendingAudit:
          break;
        case PortalSubmissionOutcome.mimeMismatch:
        case PortalSubmissionOutcome.hashMismatch:
          state = PortalSubmissionError(
            const PortalDisputeException(
              'O arquivo anexado é inválido ou está corrompido (não foi '
              'possível validar o conteúdo). Remova o anexo e tente novamente, '
              'ou envie apenas a justificativa por escrito.',
            ),
            currentState,
          );
          return;
        case PortalSubmissionOutcome.rejected:
          state = PortalSubmissionError(
            const PortalDisputeException(
              'Não foi possível validar o anexo enviado. Remova o arquivo e '
              'tente novamente, ou envie apenas a justificativa por escrito.',
            ),
            currentState,
          );
          return;
      }

      final now = DateTime.now().toUtc();
      final pseudoHash =
          sha256Client?.substring(0, 8) ??
          now.millisecondsSinceEpoch.toString().substring(5);

      state = PortalSubmissionSuccess(
        submittedAtUtc: now,
        protocol: 'VRP-${now.millisecondsSinceEpoch}-$pseudoHash',
      );
    } catch (e) {
      final Exception cause =
          e is IntegrityException || e is PortalDisputeException
          ? e as Exception
          : IntegrityException('Falha no envio: $e');
      state = PortalSubmissionError(cause, currentState);
    } finally {
      _isSubmitting = false;
    }
  }

  void reset() {
    state = const PortalSubmissionInitial();
  }
}

final portalDisputeSubmissionNotifierProvider =
    NotifierProvider.autoDispose<
      PortalDisputeSubmissionNotifier,
      PortalSubmissionState
    >(PortalDisputeSubmissionNotifier.new);
