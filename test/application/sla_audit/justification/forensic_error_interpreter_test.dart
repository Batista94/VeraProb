import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/justification/forensic_error_interpreter.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

void main() {
  const interpreter = ForensicErrorInterpreter();

  group('ForensicErrorInterpreter — Actionable PT-BR Messages', () {
    test('ForensicViolationException → "não é uma foto original"', () {
      const error = ForensicViolationException(
        message: 'Signature "<?php" found at offset 2831155',
        evidenceUrl: 'https://storage.example.com/evasion.png',
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.integrity);
      expect(
        result.userMessage,
        contains('não é uma foto original'),
        reason: 'user must learn WHY the file is invalid, not a stack trace',
      );
      expect(result.suggestedAction, contains('nova foto'));
    });

    test('DomainException containing "Invalid file type" → MIME guidance', () {
      const error = DomainException(
        'Invalid file type at evidence index 0: text/html. '
        'Allowed: image/jpeg, image/png, application/pdf, image/heic, image/heif, image/webp',
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.integrity);
      expect(result.userMessage.toLowerCase(), contains('formato'));
      expect(result.suggestedAction, contains('JPEG'));
    });

    test('DomainException containing "206" → server compatibility guidance', () {
      const error = DomainException(
        'Range request not honored: expected 206 Partial Content but got 200.',
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.infrastructure);
      expect(result.userMessage.toLowerCase(), contains('servidor'));
    });

    test('SocketException → connection-instability message', () {
      const error = SocketException('Connection refused');

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.network);
      expect(result.userMessage, contains('Conexão instável'));
      expect(result.suggestedAction.toLowerCase(), contains('tente novamente'));
    });

    test('TimeoutException → timeout message', () {
      final error = TimeoutException('Request took too long');

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.network);
      expect(result.userMessage.toLowerCase(), contains('tempo'));
    });

    test('Unknown Exception → generic fallback, no raw toString leaked', () {
      final error = Exception('RawStackTraceLeak#0x7f');

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.unknown);
      expect(
        result.userMessage,
        isNot(contains('RawStackTraceLeak')),
        reason: 'unsanitized exception strings must never reach end users',
      );
      expect(result.userMessage, contains('inesperado'));
    });

    test('interpretation is deterministic (same input → same output)', () {
      const error = ForensicViolationException(
        message: 'Signature "<?php" found',
        evidenceUrl: 'https://example.com/a.png',
      );

      final a = interpreter.interpret(error);
      final b = interpreter.interpret(error);

      expect(a.userMessage, equals(b.userMessage));
      expect(a.suggestedAction, equals(b.suggestedAction));
      expect(a.severity, equals(b.severity));
    });
  });
}
