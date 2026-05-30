import 'package:veraprob/application/admin/csv_row_mapper.dart';
import 'package:veraprob/domain/assets/i_driver_repository.dart';
import 'package:veraprob/domain/assets/i_vehicle_asset_repository.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';

/// Persists validated CSV rows by dispatching to the entity-specific
/// batch-upsert repository (Bloco 1D). Single batch round trip (INV-16).
abstract class CsvImportPersister {
  Future<int> persist({
    required String organizationId,
    required String targetEntity,
    required List<Map<String, String>> rows,
    required CsvMappingTemplate template,
    required Map<String, Contractor> resolvedContractors,
  });
}

class DefaultCsvImportPersister implements CsvImportPersister {
  DefaultCsvImportPersister({
    required IVehicleAssetRepository vehicleRepo,
    required IDriverRepository driverRepo,
    required ContractorRepository contractorRepo,
    required ContractRepository contractRepo,
    required OperationalZoneRepository zoneRepo,
    CsvRowMapper mapper = const CsvRowMapper(),
  }) : _vehicleRepo = vehicleRepo,
       _driverRepo = driverRepo,
       _contractorRepo = contractorRepo,
       _contractRepo = contractRepo,
       _zoneRepo = zoneRepo,
       _mapper = mapper;

  final IVehicleAssetRepository _vehicleRepo;
  final IDriverRepository _driverRepo;
  final ContractorRepository _contractorRepo;
  final ContractRepository _contractRepo;
  final OperationalZoneRepository _zoneRepo;
  final CsvRowMapper _mapper;

  @override
  Future<int> persist({
    required String organizationId,
    required String targetEntity,
    required List<Map<String, String>> rows,
    required CsvMappingTemplate template,
    required Map<String, Contractor> resolvedContractors,
  }) async {
    final dbRows = _mapper.toDbRows(
      targetEntity: targetEntity,
      rows: rows,
      template: template,
      resolvedContractors: resolvedContractors,
    );
    if (dbRows.isEmpty) return 0;

    return switch (targetEntity) {
      'asset' => _vehicleRepo.batchUpsertFromCsv(organizationId, dbRows),
      'operator' => _driverRepo.batchUpsertFromCsv(organizationId, dbRows),
      'contractor' => _contractorRepo.batchUpsertFromCsv(
        organizationId,
        dbRows,
      ),
      'contract' => _contractRepo.batchUpsertFromCsv(organizationId, dbRows),
      'zone' => _zoneRepo.batchUpsertFromCsv(organizationId, dbRows),
      _ => Future<int>.value(0),
    };
  }
}
