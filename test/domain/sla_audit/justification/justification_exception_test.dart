import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_exception.dart';

void main() {
  group('JustificationException', () {
    test('is-a DomainException — backwards compatible with isA matchers', () {
      const exception = JustificationException(
        'window expired',
        phase: JustificationPhase.temporal,
      );

      expect(exception, isA<DomainException>());
      expect(exception, isA<Exception>());
    });

    test('carries the failing phase for granular error handling', () {
      const exception = JustificationException(
        'evidence hash mismatch',
        phase: JustificationPhase.evidence,
      );

      expect(exception.phase, JustificationPhase.evidence);
      expect(exception.message, 'evidence hash mismatch');
    });

    test('toString tags the phase for forensic traceability', () {
      const exception = JustificationException(
        'no matching event',
        phase: JustificationPhase.linkage,
      );

      final str = exception.toString();

      expect(str, contains('JustificationException'));
      expect(str, contains('linkage'));
      expect(str, contains('no matching event'));
    });

    test('exposes every submission phase', () {
      expect(JustificationPhase.values, hasLength(6));
      expect(
        JustificationPhase.values,
        containsAll(<JustificationPhase>[
          JustificationPhase.identity,
          JustificationPhase.input,
          JustificationPhase.evidence,
          JustificationPhase.temporal,
          JustificationPhase.linkage,
          JustificationPhase.persistence,
        ]),
      );
    });
  });
}
