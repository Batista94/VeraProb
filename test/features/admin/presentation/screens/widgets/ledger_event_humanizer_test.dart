// Unit tests for humanizeLedgerEventType — the investigation-timeline label
// mapper. Pure function: no widgets, network, or DB.
//
// Guards two contracts:
//   1. Known forensic event codes map to stable Portuguese labels.
//   2. Unknown/new codes fall back to the raw string (graceful degradation),
//      so an unmapped event never renders blank.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/ledger_event_humanizer.dart';

void main() {
  group('humanizeLedgerEventType', () {
    test('maps the sanction verdict lifecycle', () {
      expect(
        humanizeLedgerEventType('SANCTION_RECOMMENDED'),
        'Infração Detectada pela Telemetria',
      );
      expect(
        humanizeLedgerEventType('VERDICT_SEALED'),
        'Veredito Confirmado pelo Auditor',
      );
      expect(
        humanizeLedgerEventType('VERDICT_REFUSED'),
        'Veredito Recusado (Isenção)',
      );
    });

    test('maps the dispute lifecycle with correct billing semantics', () {
      expect(
        humanizeLedgerEventType('SANCTION_DISPUTED'),
        'Contestação Aberta',
      );
      // ACCEPTED = contractor justification accepted → fine annulled.
      expect(
        humanizeLedgerEventType('DISPUTE_ACCEPTED'),
        'Contestação Aceita (Multa Anulada)',
      );
      // OVERTURNED = justification refused → fine upheld.
      expect(
        humanizeLedgerEventType('DISPUTE_OVERTURNED'),
        'Contestação Negada (Multa Mantida)',
      );
      expect(
        humanizeLedgerEventType('DISPUTE_RETRACTED'),
        'Contestação Retratada',
      );
    });

    test('maps justification and execution events', () {
      expect(
        humanizeLedgerEventType('JUSTIFICATION_APPROVED'),
        'Justificativa Aprovada',
      );
      expect(
        humanizeLedgerEventType('EXECUTION_BOUND'),
        'Execução Vinculada ao Ativo',
      );
      expect(
        humanizeLedgerEventType('OCCURRENCE_REGISTERED'),
        'Ocorrência Registrada',
      );
    });

    test('falls back to the raw code for unmapped event types', () {
      expect(humanizeLedgerEventType('UNKNOWN_EVENT'), 'UNKNOWN_EVENT');
      expect(humanizeLedgerEventType('SOME_FUTURE_CODE'), 'SOME_FUTURE_CODE');
      expect(humanizeLedgerEventType(''), '');
    });

    test('never returns an empty label for a non-empty known code', () {
      const knownCodes = [
        'SANCTION_RECOMMENDED',
        'VERDICT_SEALED',
        'VERDICT_REFUSED',
        'SANCTION_DISPUTED',
        'DISPUTE_ACCEPTED',
        'DISPUTE_OVERTURNED',
        'DISPUTE_RETRACTED',
        'JUSTIFICATION_SUBMITTED',
        'JUSTIFICATION_APPROVED',
        'JUSTIFICATION_REJECTED',
        'EXECUTION_BOUND',
        'EXECUTION_INHIBITED',
        'OCCURRENCE_REGISTERED',
      ];
      for (final code in knownCodes) {
        final label = humanizeLedgerEventType(code);
        expect(label, isNotEmpty);
        // A mapped code must be humanized, never echoed verbatim.
        expect(label, isNot(code), reason: '$code was not humanized');
      }
    });
  });
}
