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
}
