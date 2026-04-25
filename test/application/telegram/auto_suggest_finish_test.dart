// TDD anchor — Phase 10 Workstream 2 (MAVERICK)
// Tests auto-suggest finish logic: compliance=100% after tagging → BOT_AUTO_SUGGESTED_FINISH ledger.
// This tests the domain invariants; the actual webhook RPC call is integration-tested separately.

import 'package:flutter_test/flutter_test.dart';

// Mirrors the compliance check logic used in tg_tag callback
// (the webhook calls check_execution_compliance RPC)
bool shouldSuggestFinish({
  required bool complianceResult,
  required String? linkedSetId,
}) {
  if (linkedSetId == null) return false;
  return complianceResult;
}

// Mirrors the ledger entry type produced on auto-suggest
String autoSuggestLedgerType() => 'BOT_AUTO_SUGGESTED_FINISH';

void main() {
  group('Auto-suggest finish — compliance gate', () {
    test('compliance=true + linked trip → suggest finish', () {
      expect(
        shouldSuggestFinish(complianceResult: true, linkedSetId: 'set-abc'),
        isTrue,
      );
    });

    test('compliance=false → do not suggest finish (still pending)', () {
      expect(
        shouldSuggestFinish(complianceResult: false, linkedSetId: 'set-abc'),
        isFalse,
      );
    });

    test(
      'compliance=true but no linked trip (orphan) → do not suggest finish',
      () {
        expect(
          shouldSuggestFinish(complianceResult: true, linkedSetId: null),
          isFalse,
        );
      },
    );
  });

  group('Auto-suggest finish — ledger type', () {
    test('ledger type is BOT_AUTO_SUGGESTED_FINISH (INV-3)', () {
      expect(autoSuggestLedgerType(), equals('BOT_AUTO_SUGGESTED_FINISH'));
    });
  });
}
