// TDD RED — Bloco 1B: Auto-Match Lexical Intelligence
// Falha intencional até _autoMatch() ser implementado no notifier.
// Step 0: INV-7 (no dynamic), INV-1 (entity-scoped matching).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart'; // pr_scanner: ignore
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

ProviderContainer _makeContainer({String entity = 'contractor'}) {
  return ProviderContainer(
    overrides: [
      currentOrganizationIdProvider.overrideWith((_) => 'org-1'),
      currentSessionIdProvider.overrideWith((_) => 'session-1'),
    ],
  );
}

void main() {
  group('CsvImportFlowNotifier._autoMatch — Auto-Match Intelligence (Bloco 1B)', () {
    // ── contractor entity ─────────────────────────────────────────────────────

    test('AM-1: header "CNPJ" → contractorDocument for entity contractor', () {
      final container = _makeContainer(entity: 'contractor');
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      notifier.init('contractor');

      // Inject a pre-mapped state simulating file load with CNPJ header
      final autoMappings = notifier.autoMatchForTest(
        headers: ['CNPJ'],
        entity: 'contractor',
      );

      expect(
        autoMappings['CNPJ']?.targetField,
        equals(CsvTargetField.contractorDocument),
      );
    });

    test(
      'AM-2: header "CNPJ_CLIENTE" → contractorDocument (underscore variant)',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(csvImportFlowProvider.notifier);
        final autoMappings = notifier.autoMatchForTest(
          headers: ['CNPJ_CLIENTE'],
          entity: 'contractor',
        );

        expect(
          autoMappings['CNPJ_CLIENTE']?.targetField,
          equals(CsvTargetField.contractorDocument),
        );
      },
    );

    test('AM-3: header "Documento" → contractorDocument (pt-BR label)', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['Documento'],
        entity: 'contractor',
      );

      expect(
        autoMappings['Documento']?.targetField,
        equals(CsvTargetField.contractorDocument),
      );
    });

    // ── Bloco 1C.0: contractor name/email/contact ──────────────────────────

    test('AM-11: header "Razao Social" → contractorName for contractor', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['Razao Social'],
        entity: 'contractor',
      );

      expect(
        autoMappings['Razao Social']?.targetField,
        equals(CsvTargetField.contractorName),
      );
    });

    test('AM-12: header "Email" → contractorEmail for contractor', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['Email'],
        entity: 'contractor',
      );

      expect(
        autoMappings['Email']?.targetField,
        equals(CsvTargetField.contractorEmail),
      );
    });

    test(
      'AM-13: header "Responsavel" → contractorContactName for contractor',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(csvImportFlowProvider.notifier);
        final autoMappings = notifier.autoMatchForTest(
          headers: ['Responsavel'],
          entity: 'contractor',
        );

        expect(
          autoMappings['Responsavel']?.targetField,
          equals(CsvTargetField.contractorContactName),
        );
      },
    );

    // ── asset entity ──────────────────────────────────────────────────────────

    test('AM-4: header "Placa" → identifier for entity asset', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['Placa'],
        entity: 'asset',
      );

      expect(
        autoMappings['Placa']?.targetField,
        equals(CsvTargetField.identifier),
      );
    });

    test('AM-5: header "Capacidade" → capacity for entity asset', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['Capacidade'],
        entity: 'asset',
      );

      expect(
        autoMappings['Capacidade']?.targetField,
        equals(CsvTargetField.capacity),
      );
    });

    // ── zone entity ───────────────────────────────────────────────────────────

    test('AM-6: header "Latitude" → latitude for entity zone', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['Latitude'],
        entity: 'zone',
      );

      expect(
        autoMappings['Latitude']?.targetField,
        equals(CsvTargetField.latitude),
      );
    });

    // ── entity scope guard ────────────────────────────────────────────────────

    test(
      'AM-7: "Latitude" header for entity contractor → null (scope guard)',
      () {
        final container = _makeContainer();
        addTearDown(container.dispose);

        final notifier = container.read(csvImportFlowProvider.notifier);
        final autoMappings = notifier.autoMatchForTest(
          headers: ['Latitude'],
          entity: 'contractor',
        );

        // latitude is NOT in CsvTargetField.forEntity('contractor')
        // so even if the pattern matches, it must be null
        expect(autoMappings['Latitude'], isNull);
      },
    );

    test('AM-8: unmatchable header → null (no mapping assigned)', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['XYZ_UNKNOWN_COLUMN_777'],
        entity: 'contractor',
      );

      expect(autoMappings['XYZ_UNKNOWN_COLUMN_777'], isNull);
    });

    test('AM-9: operator entity "CPF" → operatorDocument', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['CPF'],
        entity: 'operator',
      );

      expect(
        autoMappings['CPF']?.targetField,
        equals(CsvTargetField.operatorDocument),
      );
    });

    test('AM-10: "id_externo" → externalId for any entity', () {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(csvImportFlowProvider.notifier);
      final autoMappings = notifier.autoMatchForTest(
        headers: ['id_externo'],
        entity: 'asset',
      );

      expect(
        autoMappings['id_externo']?.targetField,
        equals(CsvTargetField.externalId),
      );
    });
  });
}
