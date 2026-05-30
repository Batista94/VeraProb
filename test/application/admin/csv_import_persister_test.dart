// TDD — Bloco 1D: persister dispatch. Asserts the handler's persistence step
// routes to the correct entity repo exactly once (INV-16: one batch call).
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/admin/csv_import_persister.dart';
import 'package:veraprob/domain/assets/i_driver_repository.dart';
import 'package:veraprob/domain/assets/i_vehicle_asset_repository.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/enums/csv_target_field.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';

class _MockVehicleRepo extends Mock implements IVehicleAssetRepository {}

class _MockDriverRepo extends Mock implements IDriverRepository {}

class _MockContractorRepo extends Mock implements ContractorRepository {}

class _MockContractRepo extends Mock implements ContractRepository {}

class _MockZoneRepo extends Mock implements OperationalZoneRepository {}

CsvMappingTemplate _assetTpl() => CsvMappingTemplate(
  id: 't',
  organizationId: 'org-a',
  name: 'T',
  targetEntity: 'asset',
  columnMappings: const [
    ColumnMapping(csvHeader: 'PLACA', targetField: CsvTargetField.identifier),
    ColumnMapping(csvHeader: 'CAP', targetField: CsvTargetField.capacity),
  ],
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  late _MockVehicleRepo vehicleRepo;
  late _MockDriverRepo driverRepo;
  late _MockContractorRepo contractorRepo;
  late _MockContractRepo contractRepo;
  late _MockZoneRepo zoneRepo;
  late DefaultCsvImportPersister persister;

  setUp(() {
    vehicleRepo = _MockVehicleRepo();
    driverRepo = _MockDriverRepo();
    contractorRepo = _MockContractorRepo();
    contractRepo = _MockContractRepo();
    zoneRepo = _MockZoneRepo();
    persister = DefaultCsvImportPersister(
      vehicleRepo: vehicleRepo,
      driverRepo: driverRepo,
      contractorRepo: contractorRepo,
      contractRepo: contractRepo,
      zoneRepo: zoneRepo,
    );
  });

  group('DefaultCsvImportPersister (Bloco 1D)', () {
    test(
      'asset → vehicleRepo.batchUpsertFromCsv once, others untouched',
      () async {
        when(
          () => vehicleRepo.batchUpsertFromCsv(any(), any()),
        ).thenAnswer((_) async => 2);

        final n = await persister.persist(
          organizationId: 'org-a',
          targetEntity: 'asset',
          rows: const [
            {'PLACA': 'AAA-1', 'CAP': '40'},
            {'PLACA': 'BBB-2', 'CAP': '30'},
          ],
          template: _assetTpl(),
          resolvedContractors: const {},
        );

        expect(n, 2);
        final captured =
            verify(
                  () => vehicleRepo.batchUpsertFromCsv('org-a', captureAny()),
                ).captured.single
                as List<Map<String, dynamic>>;
        expect(captured, hasLength(2));
        expect(captured.first['plate'], 'AAA-1');
        verifyNever(() => driverRepo.batchUpsertFromCsv(any(), any()));
        verifyNever(() => contractRepo.batchUpsertFromCsv(any(), any()));
      },
    );

    test('empty input short-circuits — no repo call', () async {
      final n = await persister.persist(
        organizationId: 'org-a',
        targetEntity: 'asset',
        rows: const [],
        template: _assetTpl(),
        resolvedContractors: const {},
      );

      expect(n, 0);
      verifyNever(() => vehicleRepo.batchUpsertFromCsv(any(), any()));
    });
  });
}
