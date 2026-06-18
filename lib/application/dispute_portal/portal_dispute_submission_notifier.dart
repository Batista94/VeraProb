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

  @override
  PortalSubmissionState build() => const PortalSubmissionInitial();

  void setJustification(String text) {
    if (state is PortalSubmissionHashing ||
        state is PortalSubmissionUploading) {
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
    if (state is PortalSubmissionHashing ||
        state is PortalSubmissionUploading) {
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
    if (state is PortalSubmissionHashing ||
        state is PortalSubmissionUploading) {
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
    if (state is PortalSubmissionHashing ||
        state is PortalSubmissionUploading) {
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

      state = const PortalSubmissionUploading();
      final gateway = ref.read(portalDisputeGatewayProvider);

      await gateway.submitEvidence(
        token: token,
        justification: currentState.justification.trim(),
        file: file,
        sha256Client: sha256Client,
      );

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
