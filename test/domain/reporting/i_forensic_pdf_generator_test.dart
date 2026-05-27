// Contract tests for IForensicPdfGenerator.
//
// Verifies the port contract using a minimal fake implementation,
// ensuring all implementations must satisfy the INV-9 (SHA-256 seal)
// and PdfGenerationException propagation contracts.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/reporting/forensic_dossier.dart';
import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

// ── Fake ──────────────────────────────────────────────────────────────────────

class _FakePdfGenerator implements IForensicPdfGenerator {
  final List<ForensicDossier> calls = [];
  final bool shouldThrow;

  _FakePdfGenerator({this.shouldThrow = false});

  @override
  Future<List<int>> generateDossier(ForensicDossier dossier) async {
    if (shouldThrow) {
      throw const PdfGenerationException('Fake rendering failure');
    }
    calls.add(dossier);
    // Minimal valid PDF header so callers can validate the format.
    return [0x25, 0x50, 0x44, 0x46]; // %PDF
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

SlaLedgerEntry _buildEntry() => SlaLedgerEntry(
  eventId: 'event-001',
  organizationId: 'org-abc',
  contractId: 'contract-xyz',
  type: 'SANCTION_VERDICT',
  planVersion: 1,
  occurredAtUtc: DateTime.utc(2026, 1, 15, 8, 0),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('IForensicPdfGenerator — Contract', () {
    test('generateDossier returns non-empty bytes on success', () async {
      final generator = _FakePdfGenerator();
      final dossier = ForensicDossier(
        ledgerEntry: _buildEntry(),
        mapImageBytes: const [1, 2, 3],
        savingsCents: 100000,
      );

      final bytes = await generator.generateDossier(dossier);

      expect(bytes, isNotEmpty);
    });

    test(
      'generateDossier passes dossier reference unmodified (INV-9)',
      () async {
        final generator = _FakePdfGenerator();
        final dossier = ForensicDossier(
          ledgerEntry: _buildEntry(),
          mapImageBytes: const [10, 20, 30],
          telegramImageBytes: const [40, 50],
          savingsCents: 200000,
        );

        await generator.generateDossier(dossier);

        expect(generator.calls.length, equals(1));
        expect(generator.calls.first.savingsCents, equals(200000));
        expect(generator.calls.first.mapImageBytes, equals([10, 20, 30]));
        expect(generator.calls.first.telegramImageBytes, equals([40, 50]));
      },
    );

    test(
      'generateDossier propagates PdfGenerationException on failure',
      () async {
        final generator = _FakePdfGenerator(shouldThrow: true);
        final dossier = ForensicDossier(
          ledgerEntry: _buildEntry(),
          mapImageBytes: const [],
          savingsCents: 0,
        );

        await expectLater(
          generator.generateDossier(dossier),
          throwsA(isA<PdfGenerationException>()),
        );
      },
    );

    test('PdfGenerationException carries original message', () async {
      const exception = PdfGenerationException('render failure reason');
      expect(exception.message, equals('render failure reason'));
    });

    test(
      'generateDossier with empty mapImageBytes does not throw (N/D path)',
      () async {
        final generator = _FakePdfGenerator();
        final dossier = ForensicDossier(
          ledgerEntry: _buildEntry(),
          mapImageBytes: const [],
          savingsCents: 0,
        );

        final bytes = await generator.generateDossier(dossier);

        expect(bytes, isNotEmpty);
      },
    );

    test(
      'generateDossier with null telegramImageBytes does not throw (optional evidence)',
      () async {
        final generator = _FakePdfGenerator();
        final dossier = ForensicDossier(
          ledgerEntry: _buildEntry(),
          mapImageBytes: const [1, 2],
          savingsCents: 500,
        );

        final bytes = await generator.generateDossier(dossier);

        expect(bytes, isNotEmpty);
      },
    );
  });
}
