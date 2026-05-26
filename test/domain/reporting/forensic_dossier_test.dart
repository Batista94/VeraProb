import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/reporting/forensic_dossier.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

void main() {
  group('ForensicDossier', () {
    late SlaLedgerEntry baseEntry;

    setUp(() {
      baseEntry = SlaLedgerEntry(
        eventId: 'test-event-123',
        organizationId: 'org-123',
        type: 'TEST_EVENT',
        contractId: 'contract-123',
        planVersion: 1,
        occurredAtUtc: DateTime.utc(2026, 1, 1, 12, 0, 0),
        payload: const {'speed': 85},
      );
    });

    test('computeHash is deterministic (INV-9)', () {
      final dossier1 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        telegramImageBytes: const [4, 5, 6],
        savingsCents: 150050,
      );

      final dossier2 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        telegramImageBytes: const [4, 5, 6],
        savingsCents: 150050,
      );

      expect(dossier1.computeHash(), equals(dossier2.computeHash()));
    });

    test('computeHash changes if mapImageBytes change (INV-9)', () {
      final dossier1 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        savingsCents: 150050,
      );

      final dossier2 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 4], // Changed byte
        savingsCents: 150050,
      );

      expect(dossier1.computeHash(), isNot(equals(dossier2.computeHash())));
    });

    test('computeHash changes if telegramImageBytes change (INV-9)', () {
      final dossier1 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        telegramImageBytes: const [4, 5, 6],
        savingsCents: 150050,
      );

      final dossier2 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        telegramImageBytes: const [4, 5, 7], // Changed byte
        savingsCents: 150050,
      );

      expect(dossier1.computeHash(), isNot(equals(dossier2.computeHash())));
    });

    test('computeHash changes if savingsBrl changes (INV-9)', () {
      final dossier1 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        savingsCents: 150050,
      );

      final dossier2 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        savingsCents: 150051, // Changed saving
      );

      expect(dossier1.computeHash(), isNot(equals(dossier2.computeHash())));
    });

    test('computeHash changes if ledger entry payload changes (INV-9)', () {
      final dossier1 = ForensicDossier(
        ledgerEntry: baseEntry,
        mapImageBytes: const [1, 2, 3],
        savingsCents: 150050,
      );

      final changedEntry = SlaLedgerEntry(
        eventId: baseEntry.eventId,
        organizationId: baseEntry.organizationId,
        type: baseEntry.type,
        contractId: baseEntry.contractId,
        planVersion: baseEntry.planVersion,
        occurredAtUtc: baseEntry.occurredAtUtc,
        payload: const {'speed': 86}, // Changed payload
      );

      final dossier2 = ForensicDossier(
        ledgerEntry: changedEntry,
        mapImageBytes: const [1, 2, 3],
        savingsCents: 150050,
      );

      expect(dossier1.computeHash(), isNot(equals(dossier2.computeHash())));
    });
  });
}
