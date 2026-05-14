/// Forensic Audit Signature: CX-05-v2.3 / UX-Integrity
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb UX/Ops + Senior Engineer
///
/// Translates raw forensic exceptions into actionable, user-facing PT-BR
/// messages without leaking stack-trace details (INV-10 error visibility
/// without information disclosure).
///
/// **Determinism:** pure function — same input yields byte-identical output
/// (INV-15), so UI snapshot tests stay stable across builds.
library;

import 'dart:async';
// import 'dart:io'; (Fix web build)

import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_exception.dart';

enum ForensicErrorSeverity { integrity, infrastructure, network, unknown }

class InterpretedForensicError {
  final String userMessage;
  final String suggestedAction;
  final ForensicErrorSeverity severity;

  const InterpretedForensicError({
    required this.userMessage,
    required this.suggestedAction,
    required this.severity,
  });
}

class ForensicErrorInterpreter {
  const ForensicErrorInterpreter();

  InterpretedForensicError interpret(Object error) {
    if (error is ForensicViolationException) {
      return const InterpretedForensicError(
        userMessage:
            'O arquivo enviado não é uma foto original. '
            'Nosso verificador detectou conteúdo executável oculto no binário.',
        suggestedAction:
            'Tire uma nova foto diretamente com a câmera e envie sem editar.',
        severity: ForensicErrorSeverity.integrity,
      );
    }

    // JustificationException is a DomainException subclass — it MUST be
    // matched first so the phase-aware branch wins over the generic fallback.
    if (error is JustificationException) {
      return _interpretJustificationPhase(error.phase);
    }

    if (error is DomainException) {
      final msg = error.message;
      if (msg.contains('Invalid file type')) {
        return const InterpretedForensicError(
          userMessage:
              'Formato de arquivo não aceito. '
              'Apenas fotos e documentos originais são válidos como evidência.',
          suggestedAction:
              'Envie JPEG, PNG, HEIC, WebP ou PDF. '
              'Arquivos compactados (ZIP) e documentos de escritório não são aceitos.',
          severity: ForensicErrorSeverity.integrity,
        );
      }
      if (msg.contains('206')) {
        return const InterpretedForensicError(
          userMessage:
              'O servidor de armazenamento não respondeu no formato esperado '
              '(faltou suporte a leitura parcial 206).',
          suggestedAction:
              'Aguarde alguns instantes e tente novamente. '
              'Se persistir, contate o suporte — a infraestrutura precisa ser verificada.',
          severity: ForensicErrorSeverity.infrastructure,
        );
      }
      return const InterpretedForensicError(
        userMessage: 'Não foi possível validar a evidência no momento.',
        suggestedAction: 'Tente novamente em alguns instantes.',
        severity: ForensicErrorSeverity.infrastructure,
      );
    }

    if (error.toString().contains('SocketException')) {
      return const InterpretedForensicError(
        userMessage: 'Conexão instável detectada durante o envio da evidência.',
        suggestedAction:
            'Verifique sua rede e tente novamente. '
            'Evidências incompletas nunca são aceitas pelo sistema.',
        severity: ForensicErrorSeverity.network,
      );
    }

    if (error is TimeoutException) {
      return const InterpretedForensicError(
        userMessage: 'O envio excedeu o tempo limite de resposta do servidor.',
        suggestedAction: 'Tente novamente com uma conexão mais estável.',
        severity: ForensicErrorSeverity.network,
      );
    }

    return const InterpretedForensicError(
      userMessage: 'Ocorreu um erro inesperado durante a verificação.',
      suggestedAction:
          'Se o problema persistir, registre um chamado no suporte.',
      severity: ForensicErrorSeverity.unknown,
    );
  }

  /// Maps a [JustificationPhase] to an actionable PT-BR message.
  ///
  /// Phase-aware translation is robust against message-text drift — the UI
  /// reacts to the structural phase, not to fragile substring matching.
  InterpretedForensicError _interpretJustificationPhase(
    JustificationPhase phase,
  ) {
    switch (phase) {
      case JustificationPhase.identity:
        return const InterpretedForensicError(
          userMessage:
              'Não foi possível confirmar a identidade da organização '
              'para esta justificativa.',
          suggestedAction:
              'Recarregue a página e entre novamente. '
              'Se persistir, contate o gestor da sua organização.',
          severity: ForensicErrorSeverity.integrity,
        );
      case JustificationPhase.input:
        return const InterpretedForensicError(
          userMessage:
              'A descrição enviada não atende aos requisitos mínimos '
              'do dossiê de defesa.',
          suggestedAction:
              'Descreva o ocorrido com pelo menos 10 caracteres e '
              'selecione uma categoria válida.',
          severity: ForensicErrorSeverity.integrity,
        );
      case JustificationPhase.evidence:
        return const InterpretedForensicError(
          userMessage:
              'A evidência enviada não passou na verificação de integridade '
              '(selo SHA-256).',
          suggestedAction:
              'Anexe ao menos uma foto ou documento original e reenvie. '
              'Cada arquivo precisa de seu selo de integridade.',
          severity: ForensicErrorSeverity.integrity,
        );
      case JustificationPhase.temporal:
        return const InterpretedForensicError(
          userMessage: 'O prazo para justificar este evento já expirou.',
          suggestedAction:
              'Justificativas só são aceitas dentro da janela contratual. '
              'Contate o gestor para avaliar exceções.',
          severity: ForensicErrorSeverity.infrastructure,
        );
      case JustificationPhase.linkage:
        return const InterpretedForensicError(
          userMessage:
              'Não foi possível vincular esta justificativa a um evento '
              'operacional do veículo.',
          suggestedAction:
              'Verifique o veículo e o horário do evento. '
              'Se já existe uma justificativa para este evento, ela não pode '
              'ser duplicada.',
          severity: ForensicErrorSeverity.integrity,
        );
      case JustificationPhase.persistence:
        return const InterpretedForensicError(
          userMessage:
              'O servidor detectou divergência ao selar a evidência após '
              'o envio.',
          suggestedAction:
              'Reenvie a evidência sem editá-la. '
              'Se persistir, contate o suporte — a infraestrutura precisa '
              'ser verificada.',
          severity: ForensicErrorSeverity.infrastructure,
        );
    }
  }
}
