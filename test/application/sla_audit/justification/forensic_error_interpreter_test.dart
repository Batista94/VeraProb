import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/justification/forensic_error_interpreter.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_exception.dart';

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

    test('JustificationException(temporal) → expiration-window message', () {
      const error = JustificationException(
        'Justification window expired: event occurred 30h ago, limit is 24h.',
        phase: JustificationPhase.temporal,
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.infrastructure);
      expect(result.userMessage.toLowerCase(), contains('prazo'));
      expect(result.userMessage, isNot(contains('CX05')));
    });

    test('JustificationException(evidence) → integrity guidance', () {
      const error = JustificationException(
        'Invalid SHA-256 hash: "abc". Must be 64 hex characters.',
        phase: JustificationPhase.evidence,
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.integrity);
      expect(result.userMessage.toLowerCase(), contains('evidência'));
    });

    test('JustificationException(linkage) → linkage guidance', () {
      const error = JustificationException(
        'No matching event found for this vehicle and timestamp.',
        phase: JustificationPhase.linkage,
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.integrity);
      expect(result.userMessage.toLowerCase(), contains('evento'));
    });

    test('JustificationException(input) → input guidance', () {
      const error = JustificationException(
        'Description must be at least 10 characters.',
        phase: JustificationPhase.input,
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.integrity);
      expect(result.userMessage.toLowerCase(), contains('descrição'));
    });

    test('JustificationException(identity) → identity guidance', () {
      const error = JustificationException(
        'Invalid justification category: bogus',
        phase: JustificationPhase.identity,
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.integrity);
      expect(result.userMessage, isNot(contains('bogus')));
    });

    test('JustificationException(persistence) → infra guidance', () {
      const error = JustificationException(
        'Evidence integrity check failed: hashes do not match.',
        phase: JustificationPhase.persistence,
      );

      final result = interpreter.interpret(error);

      expect(result.severity, ForensicErrorSeverity.infrastructure);
      expect(result.userMessage.toLowerCase(), contains('servidor'));
    });

    test(
      'JustificationException is matched before generic DomainException',
      () {
        const error = JustificationException(
          'window expired',
          phase: JustificationPhase.temporal,
        );

        final result = interpreter.interpret(error);

        // Generic DomainException fallback would say "validar a evidência";
        // the phase-aware branch must win.
        expect(result.userMessage.toLowerCase(), contains('prazo'));
      },
    );

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
